import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'audio_utils.dart';

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

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _audioSubscription;
  int _recorderGeneration = 0;

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
    await _startAudioStream();
    _running = true;
    print('[VOICE] engine started, listening for wake word');
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

  Future<void> _startAudioStream() async {
    _recorder = AudioRecorder();
    _recorderGeneration++;
    final hasPerm = await _recorder!.hasPermission();
    if (!hasPerm) {
      print('[VOICE] mic permission denied');
      return;
    }
    print('[VOICE] mic permission granted, starting stream');
    final stream = await _recorder!.startStream(
      const RecordConfig(
        sampleRate: 16000,
        numChannels: 1,
        encoder: AudioEncoder.pcm16bits,
      ),
    );
    print('[VOICE] audio stream started');
    _audioSubscription = stream.listen(_onAudioData);
  }

  Future<void> _stopAudioStream() async {
    final gen = _recorderGeneration;
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    if (gen != _recorderGeneration) return;
    await _recorder?.stop();
    _recorder?.dispose();
    _recorder = null;
    print('[VOICE] audio stream stopped');
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
    await _stopAudioStream();
  }

  Future<void> resetToWakeListening() async {
    _wakeWordFired = false;
    await _startAudioStream();
    print('[VOICE] reset to wake listening');
  }

  void playWakeSound() {
    final p = AudioPlayer();
    p.play(AssetSource('audio/wake-word-detected.mp3'));
    p.onPlayerComplete.first.then((_) => p.dispose());
  }

  void playCommandFeedback() {
    final p = AudioPlayer();
    p.play(AssetSource('audio/following-command.mp3'));
    p.onPlayerComplete.first.then((_) => p.dispose());
  }

  void playUnknownFeedback() {
    final p = AudioPlayer();
    p.play(AssetSource('audio/unknown-command.mp3'));
    p.onPlayerComplete.first.then((_) => p.dispose());
  }

  Future<void> stop() async {
    _running = false;
    await _stopAudioStream();
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
