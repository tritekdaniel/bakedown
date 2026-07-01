import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_app/features/settings/presentation/providers/settings_providers.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'sherpa_engine.dart';
import 'voice_command.dart';

enum VoiceState { idle, wakeListening, wakeDetected, commandListening }

final sherpaEngineProvider = Provider<SherpaEngine>((ref) {
  final engine = SherpaEngine(
    onWakeWordDetected: () {
      ref.read(voiceStateProvider.notifier).state = VoiceState.wakeDetected;
    },
  );
  ref.onDispose(() => engine.dispose());
  return engine;
});

final speechToTextProvider = Provider<SpeechToTextProvider>((ref) {
  return SpeechToTextProvider();
});

class SpeechToTextProvider {
  final SpeechToText _stt = SpeechToText();
  bool _available = false;
  void Function(String)? _statusHandler;
  void Function(String)? _errorHandler;
  int _generation = 0;

  Future<bool> listen({
    required void Function(String text) onResult,
    required void Function(String status) onStatus,
    void Function(String error)? onError,
    required Duration listenFor,
    required Duration pauseFor,
    String localeId = 'en_US',
    bool onDevice = true,
    ListenMode listenMode = ListenMode.dictation,
    Duration silenceDebounce = const Duration(milliseconds: 1100),
  }) async {
    if (!_available) {
      _statusHandler = onStatus;
      _errorHandler = onError;
      try {
        _available = await _stt.initialize(
          onError: (error) => _errorHandler?.call(error.errorMsg),
          onStatus: (status) => _statusHandler?.call(status),
        );
      } catch (e) {
        print('[STT] initialization error: $e');
        return false;
      }
      if (!_available) {
        print('[STT] initialization failed');
        return false;
      }
    }

    final generation = ++_generation;
    Timer? silenceTimer;
    bool delivered = false;
    String lastText = '';

    void deliver(String text) {
      if (delivered || text.isEmpty || generation != _generation) return;
      delivered = true;
      silenceTimer?.cancel();
      onResult(text);
    }

    // Defer: calling back into the STT plugin (via deliver -> dispatch ->
    // stt.stop()) from inside its own status callback can hang, since the
    // plugin's stop() waits on a status transition that already just fired.
    // A microtask lets this callback's stack fully unwind first.
    void handleStatus(String status) {
      if (status == 'listening') {
        onStatus(status);
        return;
      }
      scheduleMicrotask(() {
        if (status == 'done' || status == 'notListening') {
          deliver(lastText);
        }
        onStatus(status);
      });
    }

    void handleError(String error) {
      scheduleMicrotask(() {
        deliver(lastText);
        onError?.call(error);
      });
    }

    _statusHandler = handleStatus;
    _errorHandler = handleError;

    await _stt.listen(
      onResult: (result) {
        final text = result.recognizedWords;
        if (text.isNotEmpty) {
          print('[STT] ${result.finalResult ? "final" : "partial"}: "$text"');
        }
        if (result.finalResult) {
          deliver(text);
          return;
        }
        lastText = text;
        silenceTimer?.cancel();
        if (text.isEmpty) return;
        silenceTimer = Timer(silenceDebounce, () {
          if (generation != _generation) return;
          print('[STT] debounce firing — no change for ${silenceDebounce.inMilliseconds}ms');
          deliver(lastText);
          _stt.stop();
        });
      },
      listenOptions: SpeechListenOptions(
        listenFor: listenFor,
        pauseFor: pauseFor,
        localeId: localeId,
        cancelOnError: true,
        onDevice: onDevice,
        listenMode: listenMode,
      ),
    );
    return true;
  }

  Future<void> stop() async {
    _generation++;
    _statusHandler = null;
    _errorHandler = null;
    await _stt.stop();
  }

  void dispose() {
    _generation++;
    _statusHandler = null;
    _errorHandler = null;
    _stt.stop();
  }
}

final voiceStateProvider = StateProvider<VoiceState>((ref) => VoiceState.idle);

final voiceListeningProvider = StateProvider<bool>((ref) => false);

final voiceCommandProvider = StateProvider<VoiceCommand?>((ref) => null);

final voiceCommandRawProvider = StateProvider<String?>((ref) => null);

final voiceEnabledProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).voiceEnabled;
});
