import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_app/features/timer/domain/models/timer_model.dart';

const kTimerSounds = [
  'audio/Carbon.mp3',
  'audio/Gallium.mp3',
  'audio/Helium.mp3',
  'audio/Hydrogen.mp3',
  'audio/Lithium.mp3',
  'audio/Neon.mp3',
  'audio/Oxygen.mp3',
  'audio/Plutonium.mp3',
  'audio/Rubidium.mp3',
  'audio/Strontium.mp3',
  'audio/Sulfur.mp3',
];

String soundDisplayName(String path) {
  return path
      .replaceFirst('audio/', '')
      .replaceFirst('.wav', '')
      .replaceFirst('.mp3', '');
}

final timerListProvider =
    StateNotifierProvider<TimerNotifier, List<TimerModel>>((ref) {
  return TimerNotifier();
});

final activeTimersProvider = Provider<List<TimerModel>>((ref) {
  final all = ref.watch(timerListProvider);
  return all
      .where((t) =>
          t.status == TimerStatus.running || t.status == TimerStatus.paused)
      .toList();
});

final completedTimersProvider = Provider<List<TimerModel>>((ref) {
  final all = ref.watch(timerListProvider);
  return all.where((t) => t.status == TimerStatus.completed).toList();
});

final alarmingTimersProvider = Provider<List<TimerModel>>((ref) {
  return ref.watch(timerListProvider).where((t) => t.isAlarming).toList();
});

class TimerNotifier extends StateNotifier<List<TimerModel>> {
  final Map<String, Timer> _tickers = {};
  final Map<String, AudioPlayer> _players = {};
  final Map<String, Timer> _alarmStopTimers = {};
  int _nextId = 0;

  TimerNotifier() : super([]);

  @override
  void dispose() {
    for (final t in _tickers.values) {
      t.cancel();
    }
    _tickers.clear();
    for (final t in _alarmStopTimers.values) {
      t.cancel();
    }
    _alarmStopTimers.clear();
    for (final p in _players.values) {
      p.dispose();
    }
    _players.clear();
    super.dispose();
  }

  String get _nextTimerId => 'tmr_${_nextId++}';

  void addTimer(int seconds, {String? label, String? soundFile}) {
    final id = _nextTimerId;
    final model = TimerModel(
      id: id,
      label: label ?? 'Timer ${state.length + 1}',
      total: Duration(seconds: seconds),
      elapsed: Duration.zero,
      status: TimerStatus.running,
      soundFile: soundFile ?? 'audio/Helium.mp3',
      createdAt: DateTime.now(),
    );
    state = [...state, model];
    _tickers[id] =
        Timer.periodic(const Duration(seconds: 1), (_) => _tick(id));
  }

  void _tick(String id) {
    state = state.map((t) {
      if (t.id != id) return t;
      final newElapsed = t.elapsed + const Duration(seconds: 1);
      if (newElapsed >= t.total) {
        _tickers[id]?.cancel();
        _tickers.remove(id);
        _playAlarm(id, t.soundFile);
        return t.copyWith(
          elapsed: t.total,
          status: TimerStatus.completed,
          isAlarming: true,
        );
      }
      return t.copyWith(elapsed: newElapsed);
    }).toList();
  }

  Future<void> _playAlarm(String id, String soundFile) async {
    try {
      _alarmStopTimers[id]?.cancel();
      final player = AudioPlayer();
      _players[id] = player;
      player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource(soundFile));
      _alarmStopTimers[id] = Timer(const Duration(seconds: 60), () {
        dismissAlarm(id);
      });
    } catch (_) {}
  }

  void _playCloseSound() {
    try {
      final player = AudioPlayer();
      player.onPlayerComplete.first.then((_) => player.dispose());
      player.play(AssetSource('audio/close-timer.mp3'));
    } catch (_) {}
  }

  void dismissAlarm([String? id]) {
    _playCloseSound();
    if (id != null) {
      _alarmStopTimers[id]?.cancel();
      _alarmStopTimers.remove(id);
      _players[id]?.stop();
      _players[id]?.dispose();
      _players.remove(id);
      state = state.map((t) {
        if (t.id == id) return t.copyWith(isAlarming: false);
        return t;
      }).toList();
    } else {
      for (final t in _alarmStopTimers.values) {
        t.cancel();
      }
      _alarmStopTimers.clear();
      for (final p in _players.values) {
        p.stop();
        p.dispose();
      }
      _players.clear();
      state = state.map((t) {
        if (t.isAlarming) return t.copyWith(isAlarming: false);
        return t;
      }).toList();
    }
  }

  void cancelTimer(String? label) {
    _playCloseSound();
    final idx = label != null
        ? state.indexWhere(
            (t) => t.label == label && t.status != TimerStatus.completed)
        : state.indexWhere((t) => t.status == TimerStatus.running);
    if (idx == -1) return;
    final id = state[idx].id;
    _tickers[id]?.cancel();
    _tickers.remove(id);
    _cleanupAlarm(id);
    state = [
      for (int i = 0; i < state.length; i++)
        if (i == idx) state[i].copyWith(status: TimerStatus.cancelled) else state[i],
    ];
  }

  void _cleanupAlarm(String id) {
    _alarmStopTimers[id]?.cancel();
    _alarmStopTimers.remove(id);
    _players[id]?.stop();
    _players[id]?.dispose();
    _players.remove(id);
  }

  void pauseTimer(String? label) {
    final idx = label != null
        ? state.indexWhere(
            (t) => t.label == label && t.status == TimerStatus.running)
        : state.indexWhere((t) => t.status == TimerStatus.running);
    if (idx == -1) return;
    final id = state[idx].id;
    _tickers[id]?.cancel();
    _tickers.remove(id);
    state = [
      for (int i = 0; i < state.length; i++)
        if (i == idx) state[i].copyWith(status: TimerStatus.paused) else state[i],
    ];
  }

  void resumeTimer(String? label) {
    final idx = label != null
        ? state.indexWhere(
            (t) => t.label == label && t.status == TimerStatus.paused)
        : state.indexWhere((t) => t.status == TimerStatus.paused);
    if (idx == -1) return;
    final id = state[idx].id;
    state = [
      for (int i = 0; i < state.length; i++)
        if (i == idx) state[i].copyWith(status: TimerStatus.running) else state[i],
    ];
    _tickers[id] =
        Timer.periodic(const Duration(seconds: 1), (_) => _tick(id));
  }

  void dismissCompleted(String id) {
    _playCloseSound();
    _tickers.remove(id);
    _cleanupAlarm(id);
    state = state.where((t) => t.id != id).toList();
  }

  String? findTimerByLabel(String label) {
    final lower = label.toLowerCase();
    for (final t in state) {
      if (t.label.toLowerCase() == lower) {
        return t.id;
      }
    }
    for (final t in state) {
      if (t.status != TimerStatus.completed &&
          t.label.toLowerCase().contains(lower)) {
        return t.id;
      }
    }
    return null;
  }
}
