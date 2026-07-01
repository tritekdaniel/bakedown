enum TimerStatus { running, paused, completed, cancelled }

class TimerModel {
  final String id;
  final String label;
  final Duration total;
  final Duration elapsed;
  final TimerStatus status;
  final DateTime createdAt;
  final String soundFile;
  final bool isAlarming;

  const TimerModel({
    required this.id,
    required this.label,
    required this.total,
    required this.elapsed,
    required this.status,
    this.soundFile = 'audio/Helium.mp3',
    this.isAlarming = false,
    required this.createdAt,
  });

  Duration get remaining => total - elapsed;

  double get progress =>
      total.inMilliseconds > 0 ? elapsed.inMilliseconds / total.inMilliseconds : 0.0;

  TimerModel copyWith({
    String? id,
    String? label,
    Duration? total,
    Duration? elapsed,
    TimerStatus? status,
    DateTime? createdAt,
    String? soundFile,
    bool? isAlarming,
  }) {
    return TimerModel(
      id: id ?? this.id,
      label: label ?? this.label,
      total: total ?? this.total,
      elapsed: elapsed ?? this.elapsed,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      soundFile: soundFile ?? this.soundFile,
      isAlarming: isAlarming ?? this.isAlarming,
    );
  }
}
