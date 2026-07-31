package com.recipeapp.recipe_app

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class WakeWordAudioSource(
    private val context: Context,
    binaryMessenger: io.flutter.plugin.common.BinaryMessenger,
) {
    companion object {
        private const val METHOD_CHANNEL = "recipe_app/wake_word_audio/methods"
        private const val EVENT_CHANNEL = "recipe_app/wake_word_audio/events"

        private const val SAMPLE_RATE = 16000
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
        private const val CHUNK_DURATION_MS = 100
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private var audioRecord: AudioRecord? = null
    private var readThread: Thread? = null
    @Volatile private var isRecording = false
    @Volatile private var hasFocus = false

    private var eventSink: EventChannel.EventSink? = null

    private val focusChangeListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        when (focusChange) {
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                hasFocus = false
                sendEvent(mapOf("type" to "focusLost", "reason" to focusChange.toString()))
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                hasFocus = true
                sendEvent(mapOf("type" to "focusGained"))
            }
        }
    }

    private val methodChannel = MethodChannel(binaryMessenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(binaryMessenger, EVENT_CHANNEL)

    init {
        methodChannel.setMethodCallHandler { call, result -> handleMethodCall(call, result) }
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                eventSink = sink
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val ok = start()
                result.success(ok)
            }
            "stop" -> {
                stop()
                result.success(true)
            }
            "hasPermission" -> {
                val granted = context.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) ==
                        android.content.pm.PackageManager.PERMISSION_GRANTED
                result.success(granted)
            }
            else -> result.notImplemented()
        }
    }

    private fun sendEvent(event: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(event)
        }
    }

    private fun requestFocus(): Boolean {
        @Suppress("DEPRECATION")
        val res = audioManager.requestAudioFocus(
            focusChangeListener,
            AudioManager.STREAM_MUSIC,
            AudioManager.AUDIOFOCUS_GAIN_TRANSIENT,
        )
        hasFocus = res == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        return hasFocus
    }

    private fun abandonFocus() {
        @Suppress("DEPRECATION")
        audioManager.abandonAudioFocus(focusChangeListener)
        hasFocus = false
    }

    @Synchronized
    fun start(): Boolean {
        if (isRecording) return true

        val granted = context.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
        if (!granted) {
            sendEvent(mapOf("type" to "error", "message" to "RECORD_AUDIO permission not granted"))
            return false
        }

        requestFocus()

        val minBufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
        if (minBufferSize == AudioRecord.ERROR || minBufferSize == AudioRecord.ERROR_BAD_VALUE) {
            sendEvent(mapOf("type" to "error", "message" to "AudioRecord.getMinBufferSize failed"))
            return false
        }

        val bufferSize = minBufferSize * 3

        val record = try {
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                SAMPLE_RATE,
                CHANNEL_CONFIG,
                AUDIO_FORMAT,
                bufferSize,
            )
        } catch (e: Exception) {
            sendEvent(mapOf("type" to "error", "message" to "AudioRecord constructor failed: ${e.message}"))
            return false
        }

        if (record.state != AudioRecord.STATE_INITIALIZED) {
            sendEvent(mapOf("type" to "error", "message" to "AudioRecord failed to initialize (state=${record.state})"))
            record.release()
            return false
        }

        audioRecord = record
        isRecording = true

        try {
            record.startRecording()
        } catch (e: Exception) {
            sendEvent(mapOf("type" to "error", "message" to "AudioRecord.startRecording failed: ${e.message}"))
            isRecording = false
            record.release()
            audioRecord = null
            return false
        }

        val chunkFrames = SAMPLE_RATE * CHUNK_DURATION_MS / 1000
        val chunkBytes = chunkFrames * 2

        val thread = Thread({
            val buffer = ByteArray(chunkBytes)
            while (isRecording) {
                val rec = audioRecord ?: break
                val bytesRead = try {
                    rec.read(buffer, 0, buffer.size)
                } catch (e: Exception) {
                    sendEvent(mapOf("type" to "error", "message" to "AudioRecord.read threw: ${e.message}"))
                    break
                }
                if (bytesRead > 0) {
                    val chunk = buffer.copyOf(bytesRead)
                    mainHandler.post {
                        eventSink?.success(mapOf("type" to "data", "bytes" to chunk))
                    }
                } else if (bytesRead < 0) {
                    sendEvent(mapOf("type" to "error", "message" to "AudioRecord.read returned error code $bytesRead"))
                    break
                }
            }
        }, "WakeWordAudioReadThread")
        thread.priority = Thread.MAX_PRIORITY
        readThread = thread
        thread.start()

        return true
    }

    @Synchronized
    fun stop() {
        isRecording = false
        readThread?.let {
            try {
                it.join(500)
            } catch (_: InterruptedException) {
            }
        }
        readThread = null

        audioRecord?.let { rec ->
            try {
                if (rec.state == AudioRecord.STATE_INITIALIZED) {
                    rec.stop()
                }
            } catch (_: Exception) {
            }
            rec.release()
        }
        audioRecord = null

        abandonFocus()
    }

    fun dispose() {
        stop()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }
}
