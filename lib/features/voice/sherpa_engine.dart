import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'audio_utils.dart';
import 'native_audio_source.dart';

class SherpaEngine {
  SherpaEngine({
    required this.onWakeWordDetected,
  });

  final VoidCallback onWakeWordDetected;

  static bool _bindingsInitialized = false;

  static final List<String> _kwsFiles = [
    'assets/sherpa/kws/encoder.onnx',
    'assets/sherpa/kws/decoder.onnx',
    'assets/sherpa/kws/joiner.onnx',
    'assets/sherpa/kws/tokens.txt',
    'assets/sherpa/kws/bpe.model',
    'assets/sherpa/kws/keywords.txt',
  ];

  static void initBindings() {
    if (_bindingsInitialized) return;
    sherpa.initBindings();
    _bindingsInitialized = true;
  }

  bool _running = false;
  bool _initialized = false;
  bool _wakeWordFired = false;

  sherpa.KeywordSpotter? _kws;
  sherpa.OnlineStream? _kwsStream;

  // --- Native audio path (primary) ---
  NativeAudioSource? _nativeSource;
  StreamSubscription<Uint8List>? _nativeDataSub;
  StreamSubscription<AudioSourceEvent>? _nativeEventSub;
  bool _useNativeAudio = true;

  // --- record-package audio path (fallback only) ---
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _recorderSubscription;
  int _recorderGeneration = 0;

  static final _duckAudioContext = AudioContext(
    android: AudioContextAndroid(
      isSpeakerphoneOn: false,
      stayAwake: false,
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.alarm,
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.ambient,
      options: {AVAudioSessionOptions.mixWithOthers},
    ),
  );

  String? _kwsDir;

  Future<void> init() async {
    if (_initialized) return;
    await _copyModels();
    _initialized = true;
  }

  Future<void> start() async {
    if (_running) return;
    if (!_initialized) await init();
    _initKws();
    await _startAudio();
    _running = true;
    print('[VOICE] engine started, listening for wake word (native=$_useNativeAudio)');
  }

  void _initKws() {
    _kws?.free();
    final config = sherpa.KeywordSpotterConfig(
      feat: sherpa.FeatureConfig(sampleRate: 16000, featureDim: 80),
      model: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: p.join(_kwsDir!, 'encoder.onnx'),
          decoder: p.join(_kwsDir!, 'decoder.onnx'),
          joiner: p.join(_kwsDir!, 'joiner.onnx'),
        ),
        tokens: p.join(_kwsDir!, 'tokens.txt'),
        bpeVocab: p.join(_kwsDir!, 'bpe.model'),
        modelingUnit: 'bpe',
        modelType: 'zipformer2',
        numThreads: 2,
      ),
      keywordsFile: p.join(_kwsDir!, 'keywords.txt'),
      keywordsThreshold: 0.15,
      keywordsScore: 1.0,
      maxActivePaths: 4,
      numTrailingBlanks: 1,
    );
    _kws = sherpa.KeywordSpotter(config);
    _kwsStream?.free();
    _kwsStream = _kws!.createStream();
  }

  Future<void> _copyModels() async {
    final dir = await getApplicationSupportDirectory();
    final sherpaDir = Directory(p.join(dir.path, 'sherpa'));
    if (!await sherpaDir.exists()) {
      await sherpaDir.create(recursive: true);
    }
    _kwsDir = p.join(sherpaDir.path, 'kws');
    final target = Directory(_kwsDir!);
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    for (final assetPath in _kwsFiles) {
      try {
        final data = await rootBundle.load(assetPath);
        final name = p.basename(assetPath);
        await File(p.join(_kwsDir!, name)).writeAsBytes(data.buffer.asUint8List());
      } catch (e) {
        print('[VOICE] failed to copy $assetPath: $e');
      }
    }
  }

  Future<void> _startAudio() async {
    await _stopAudio();

    _nativeSource = NativeAudioSource();
    _wireNativeEvents(_nativeSource!);

    final nativeStarted = await _nativeSource!.start();
    if (nativeStarted) {
      _useNativeAudio = true;
      _nativeDataSub = _nativeSource!.onData.listen(_onAudioData);
      print('[VOICE] native audio source started');
      return;
    }

    print('[VOICE] native audio source failed to start -- falling back to record package');
    _nativeSource?.dispose();
    _nativeSource = null;
    _useNativeAudio = false;
    await _startRecorderFallback();
  }

  void _wireNativeEvents(NativeAudioSource source) {
    _nativeEventSub?.cancel();
    _nativeEventSub = source.onEvent.listen((event) {
      switch (event) {
        case AudioFocusLost(:final reason):
          print('[VOICE] audio focus lost: $reason');
        case AudioFocusGained():
          print('[VOICE] audio focus regained');
        case AudioSourceError(:final message):
          print('[VOICE] native audio error: $message -- falling back to record package');
          _handleNativeFailureMidStream();
      }
    });
  }

  Future<void> _handleNativeFailureMidStream() async {
    if (!_useNativeAudio) return;
    _useNativeAudio = false;
    await _nativeDataSub?.cancel();
    _nativeDataSub = null;
    _nativeSource?.dispose();
    _nativeSource = null;
    await _startRecorderFallback();
  }

  Future<void> _startRecorderFallback() async {
    _recorder = AudioRecorder();
    _recorderGeneration++;
    final myGen = _recorderGeneration;
    final hasPerm = await _recorder!.hasPermission();
    if (!hasPerm) {
      print('[VOICE] mic permission denied (fallback path)');
      return;
    }
    final stream = await _recorder!.startStream(
      const RecordConfig(
        sampleRate: 16000,
        numChannels: 1,
        encoder: AudioEncoder.pcm16bits,
      ),
    );
    print('[VOICE] fallback (record package) audio stream started');
    _recorderSubscription = stream.listen((data) {
      if (myGen != _recorderGeneration) return;
      _onAudioData(data);
    });
  }

  Future<void> _stopAudio() async {
    await _nativeDataSub?.cancel();
    _nativeDataSub = null;
    await _nativeEventSub?.cancel();
    _nativeEventSub = null;
    if (_nativeSource != null) {
      await _nativeSource!.stop();
      _nativeSource!.dispose();
      _nativeSource = null;
    }

    _recorderGeneration++;
    await _recorderSubscription?.cancel();
    _recorderSubscription = null;
    await _recorder?.stop();
    _recorder?.dispose();
    _recorder = null;
  }

  void _onAudioData(Uint8List data) {
    if (_kwsStream == null || _kws == null || _wakeWordFired) return;
    final samples = convertBytesToFloat32(data);
    _kwsStream!.acceptWaveform(samples: samples, sampleRate: 16000);
    while (_kws!.isReady(_kwsStream!)) {
      _kws!.decode(_kwsStream!);
    }
    final result = _kws!.getResult(_kwsStream!);
    if (result.keyword.isNotEmpty) {
      _wakeWordFired = true;
      print('[VOICE] KWS keyword detected: ${result.keyword}');
      _kws!.reset(_kwsStream!);
      onWakeWordDetected();
    }
  }

  Future<void> stopMic() async {
    await _stopAudio();
  }

  Future<void> resetToWakeListening() async {
    _wakeWordFired = false;
    await _startAudio();
    print('[VOICE] reset to wake listening');
  }

  Future<void> playWakeSound() async {
    final p = AudioPlayer();
    await p.setAudioContext(_duckAudioContext);
    await p.play(AssetSource('audio/wake-word-detected.mp3'));
    p.onPlayerComplete.first.then((_) => p.dispose());
  }

  Future<void> playCommandFeedback() async {
    final p = AudioPlayer();
    await p.setAudioContext(_duckAudioContext);
    await p.play(AssetSource('audio/following-command.mp3'));
    p.onPlayerComplete.first.then((_) => p.dispose());
  }

  Future<void> playUnknownFeedback() async {
    final p = AudioPlayer();
    await p.setAudioContext(_duckAudioContext);
    await p.play(AssetSource('audio/unknown-command.mp3'));
    p.onPlayerComplete.first.then((_) => p.dispose());
  }

  Future<void> playVoiceActivated() async {
    final p = AudioPlayer();
    await p.setAudioContext(_duckAudioContext);
    await p.play(AssetSource('audio/voice-activated.mp3'));
    p.onPlayerComplete.first.then((_) => p.dispose());
  }

  Future<void> playVoiceDeactivated() async {
    final p = AudioPlayer();
    await p.setAudioContext(_duckAudioContext);
    await p.play(AssetSource('audio/voice-deactivated.mp3'));
    p.onPlayerComplete.first.then((_) => p.dispose());
  }

  Future<void> stop() async {
    _running = false;
    await _stopAudio();
    _kws?.free();
    _kws = null;
    _kwsStream?.free();
    _kwsStream = null;
    print('[VOICE] engine stopped');
  }

  void dispose() {
    stop();
    _wakeWordFired = false;
    _recorderGeneration++;
  }
}
