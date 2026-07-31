import 'dart:async';
import 'package:flutter/services.dart';

sealed class AudioSourceEvent {}

class AudioFocusLost extends AudioSourceEvent {
  final String reason;
  AudioFocusLost(this.reason);
}

class AudioFocusGained extends AudioSourceEvent {}

class AudioSourceError extends AudioSourceEvent {
  final String message;
  AudioSourceError(this.message);
}

class NativeAudioSource {
  static const _methodChannel = MethodChannel('recipe_app/wake_word_audio/methods');
  static const _eventChannel = EventChannel('recipe_app/wake_word_audio/events');

  StreamSubscription? _rawSubscription;
  final _dataController = StreamController<Uint8List>.broadcast();
  final _eventController = StreamController<AudioSourceEvent>.broadcast();

  Stream<Uint8List> get onData => _dataController.stream;
  Stream<AudioSourceEvent> get onEvent => _eventController.stream;

  bool _listening = false;

  void _ensureListening() {
    if (_listening) return;
    _listening = true;
    _rawSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is! Map) return;
        switch (event['type']) {
          case 'data':
            final bytes = event['bytes'];
            if (bytes is Uint8List) {
              _dataController.add(bytes);
            } else if (bytes is List<int>) {
              _dataController.add(Uint8List.fromList(bytes));
            }
          case 'focusLost':
            _eventController.add(AudioFocusLost((event['reason'] ?? 'unknown').toString()));
          case 'focusGained':
            _eventController.add(AudioFocusGained());
          case 'error':
            _eventController.add(AudioSourceError((event['message'] ?? 'unknown error').toString()));
        }
      },
      onError: (Object error, StackTrace stack) {
        _eventController.add(AudioSourceError('EventChannel error: $error'));
      },
    );
  }

  Future<bool> hasPermission() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('hasPermission');
      return result ?? false;
    } catch (e) {
      _eventController.add(AudioSourceError('hasPermission failed: $e'));
      return false;
    }
  }

  Future<bool> start() async {
    _ensureListening();
    try {
      final result = await _methodChannel.invokeMethod<bool>('start');
      return result ?? false;
    } on PlatformException catch (e) {
      _eventController.add(AudioSourceError('start() PlatformException: ${e.message}'));
      return false;
    } catch (e) {
      _eventController.add(AudioSourceError('start() failed: $e'));
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _methodChannel.invokeMethod('stop');
    } catch (e) {
      _eventController.add(AudioSourceError('stop() failed: $e'));
    }
  }

  void dispose() {
    _rawSubscription?.cancel();
    _rawSubscription = null;
    _listening = false;
    _dataController.close();
    _eventController.close();
  }
}
