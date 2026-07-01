import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_app/features/tts/domain/models/tts_service.dart';

class TtsState {
  final List<String> phrases;
  final int currentIndex;
  final TtsStatus status;

  const TtsState({
    this.phrases = const [],
    this.currentIndex = 0,
    this.status = TtsStatus.idle,
  });

  String get currentPhrase =>
      phrases.isNotEmpty && currentIndex < phrases.length
          ? phrases[currentIndex]
          : '';

  bool get isActive => status == TtsStatus.speaking || status == TtsStatus.paused;

  TtsState copyWith({
    List<String>? phrases,
    int? currentIndex,
    TtsStatus? status,
  }) {
    return TtsState(
      phrases: phrases ?? this.phrases,
      currentIndex: currentIndex ?? this.currentIndex,
      status: status ?? this.status,
    );
  }
}

final ttsServiceProvider = Provider<TtsService>((ref) {
  final service = TtsService();
  ref.onDispose(() => service.dispose());
  return service;
});

final ttsStateProvider =
    StateNotifierProvider<TtsNotifier, TtsState>((ref) {
  final service = ref.watch(ttsServiceProvider);
  return TtsNotifier(service);
});

class TtsNotifier extends StateNotifier<TtsState> {
  final TtsService _service;
  StreamSubscription<TtsStatus>? _sub;
  bool _suppressNextIdle = false;

  TtsNotifier(this._service) : super(const TtsState()) {
    _sub = _service.statusStream.listen(_onTtsStatus);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _service.stop();
    super.dispose();
  }

  void _onTtsStatus(TtsStatus s) {
    if (_suppressNextIdle) {
      _suppressNextIdle = false;
      return;
    }
    if (s == TtsStatus.idle && state.isActive) {
      if (state.currentIndex < state.phrases.length - 1) {
        final next = state.currentIndex + 1;
        state = state.copyWith(currentIndex: next, status: TtsStatus.speaking);
        try {
          _service.speak(state.phrases[next]);
        } catch (_) {}
      } else {
        state = state.copyWith(status: TtsStatus.idle);
      }
    }
  }

  Future<void> init() async {
    await _service.initialize();
  }

  Future<void> speakPhrases(List<String> phrases) async {
    await _service.stop();
    if (phrases.isEmpty) return;
    state = TtsState(
      phrases: phrases,
      currentIndex: 0,
      status: TtsStatus.speaking,
    );
    await _service.speak(phrases[0]);
  }

  Future<void> next() async {
    if (state.phrases.isEmpty) return;
    final next = state.currentIndex + 1;
    if (next >= state.phrases.length) return;
    _suppressNextIdle = true;
    await _service.stop();
    state = state.copyWith(currentIndex: next, status: TtsStatus.speaking);
    await _service.speak(state.phrases[next]);
  }

  Future<void> previous() async {
    if (state.phrases.isEmpty) return;
    final prev = state.currentIndex - 1;
    if (prev < 0) return;
    _suppressNextIdle = true;
    await _service.stop();
    state = state.copyWith(currentIndex: prev, status: TtsStatus.speaking);
    await _service.speak(state.phrases[prev]);
  }

  Future<void> stop() async {
    await _service.stop();
    state = const TtsState();
  }

  Future<void> pause() async {
    await _service.pause();
    state = state.copyWith(status: TtsStatus.paused);
  }

  Future<void> resume() async {
    if (state.phrases.isEmpty) return;
    state = state.copyWith(status: TtsStatus.speaking);
    await _service.speak(state.currentPhrase);
  }

  void clear() {
    _service.stop();
    state = const TtsState();
  }
}
