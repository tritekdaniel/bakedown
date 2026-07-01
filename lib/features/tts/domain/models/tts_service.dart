import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum TtsStatus { idle, speaking, paused, unavailable }

class TtsService {
  FlutterTts? _tts;
  TtsStatus _status = TtsStatus.idle;
  final _statusController = StreamController<TtsStatus>.broadcast();

  TtsStatus get status => _status;
  Stream<TtsStatus> get statusStream => _statusController.stream;

  void _setStatus(TtsStatus s) {
    _status = s;
    _statusController.add(s);
  }

  Future<bool> initialize() async {
    if (_tts != null) return true;
    if (!kIsWeb &&
        defaultTargetPlatform != TargetPlatform.android) {
      _setStatus(TtsStatus.unavailable);
      return false;
    }
    try {
      _tts = FlutterTts();
      await _tts!.setLanguage('en-US');
      await _tts!.setSpeechRate(0.45);
      await _tts!.setPitch(1.0);
      _tts!.setCompletionHandler(() => _setStatus(TtsStatus.idle));
      _tts!.setCancelHandler(() => _setStatus(TtsStatus.idle));
      _tts!.setErrorHandler((_) => _setStatus(TtsStatus.idle));
      _setStatus(TtsStatus.idle);
      return true;
    } catch (_) {
      _setStatus(TtsStatus.unavailable);
      return false;
    }
  }

  Future<void> speak(String text) async {
    if (_tts == null || _status == TtsStatus.unavailable) return;
    _setStatus(TtsStatus.speaking);
    await _tts!.speak(text);
  }

  Future<void> stop() async {
    if (_tts == null) return;
    await _tts!.stop();
    _setStatus(TtsStatus.idle);
  }

  Future<void> pause() async {
    if (_tts == null) return;
    await _tts!.pause();
    _setStatus(TtsStatus.paused);
  }

  Future<bool> isLanguageAvailable(String lang) async {
    if (_tts == null) return false;
    try {
      return await _tts!.isLanguageAvailable(lang) ?? false;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _tts?.stop();
    _tts = null;
    _statusController.close();
  }
}
