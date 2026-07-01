import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_app/features/timer/domain/models/timer_model.dart';
import 'package:recipe_app/features/timer/presentation/providers/timer_providers.dart';

class TimerOverlay extends ConsumerStatefulWidget {
  const TimerOverlay({super.key});

  @override
  ConsumerState<TimerOverlay> createState() => _TimerOverlayState();
}

class _TimerOverlayState extends ConsumerState<TimerOverlay> {
  final Map<String, ValueNotifier<Offset>> _positionNotifiers = {};
  final Map<String, Offset> _dragOrigins = {};

  ValueNotifier<Offset> _notifierFor(String id, Offset initial) {
    return _positionNotifiers.putIfAbsent(id, () => ValueNotifier(initial));
  }

  @override
  void didUpdateWidget(TimerOverlay old) {
    super.didUpdateWidget(old);
    final active = ref.read(activeTimersProvider);
    final alarming = ref.read(alarmingTimersProvider);
    final liveIds = {
      ...active.map((t) => t.id),
      ...alarming.map((t) => t.id),
    };
    _positionNotifiers.keys
        .where((id) => !liveIds.contains(id))
        .toList()
        .forEach((id) {
      _positionNotifiers.remove(id)?.dispose();
      _dragOrigins.remove(id);
    });
  }

  @override
  void dispose() {
    for (final n in _positionNotifiers.values) {
      n.dispose();
    }
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeTimersProvider);
    final alarming = ref.watch(alarmingTimersProvider);
    final all = [...active, ...alarming];
    if (all.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final screen = MediaQuery.of(context).size;

    return SizedBox.expand(
      child: Stack(
        clipBehavior: Clip.none,
        children: all.asMap().entries
            .map((e) => _buildTimerWidget(e.value, e.key, theme, screen))
            .toList(),
      ),
    );
  }

  Widget _buildTimerWidget(
      TimerModel timer, int index, ThemeData theme, Size screen) {
    final initial = Offset(screen.width - 190.0, 80.0 + index * 110.0);
    final notifier = _notifierFor(timer.id, initial);

    return ValueListenableBuilder<Offset>(
      valueListenable: notifier,
      builder: (context, pos, child) => Positioned(
        left: pos.dx,
        top: pos.dy,
        child: Listener(
          onPointerDown: (e) {
            if (e.localPosition.dy > 62) return;
            _dragOrigins[timer.id] = e.position - pos;
          },
          onPointerMove: (e) {
            final origin = _dragOrigins[timer.id];
            if (origin == null) return;
            notifier.value = Offset(
              (e.position.dx - origin.dx).clamp(0.0, screen.width - 180),
              (e.position.dy - origin.dy).clamp(0.0, screen.height - 200),
            );
          },
          onPointerUp: (_) => _dragOrigins.remove(timer.id),
          child: child!,
        ),
      ),
      child: _buildCard(timer, theme),
    );
  }

  Widget _buildCard(TimerModel timer, ThemeData theme) {
    return Container(
      width: 180,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 12, 8),
              child: Row(
                children: [
                  _buildArc(timer, theme),
                  const SizedBox(width: 10),
                  _buildInfo(timer, theme),
                ],
              ),
            ),
            Divider(
                height: 1,
                thickness: 0.5,
                color: theme.colorScheme.outlineVariant),
            _buildFooter(timer, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildArc(TimerModel timer, ThemeData theme) {
    final color = timer.isAlarming
        ? theme.colorScheme.error
        : timer.status == TimerStatus.paused
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.primary;

    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: timer.progress.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            builder: (context, value, _) => CustomPaint(
              size: const Size(40, 40),
              painter: _ArcPainter(
                progress: value,
                color: color,
                trackColor: theme.colorScheme.outlineVariant,
              ),
            ),
          ),
          Icon(
            timer.isAlarming
                ? Icons.alarm
                : timer.status == TimerStatus.paused
                    ? Icons.pause
                    : Icons.timer,
            size: 14,
            color: color,
          ),
        ],
      ),
    );
  }

  Widget _buildInfo(TimerModel timer, ThemeData theme) {
    final labelColor = theme.colorScheme.onSurfaceVariant;
    final timeColor = timer.isAlarming
        ? theme.colorScheme.error
        : timer.status == TimerStatus.paused
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.onSurface;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            timer.label,
            style: theme.textTheme.labelSmall?.copyWith(color: labelColor),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            timer.isAlarming ? 'DONE!' : _formatDuration(timer.remaining),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: timeColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(TimerModel timer, ThemeData theme) {
    final dangerColor = theme.colorScheme.error;
    final dividerColor = theme.colorScheme.outlineVariant;

    if (timer.isAlarming) {
      return IntrinsicHeight(
        child: Row(
          children: [
            _footerBtn(Icons.alarm_off, 'Dismiss', dangerColor,
                () => ref.read(timerListProvider.notifier).dismissAlarm(timer.id)),
          ],
        ),
      );
    }
    return IntrinsicHeight(
      child: Row(
        children: [
          if (timer.status == TimerStatus.running)
            _footerBtn(Icons.pause, 'Pause', null,
                () => ref.read(timerListProvider.notifier).pauseTimer(timer.label)),
          if (timer.status == TimerStatus.paused)
            _footerBtn(Icons.play_arrow, 'Resume', null,
                () => ref.read(timerListProvider.notifier).resumeTimer(timer.label)),
          if (timer.status == TimerStatus.running || timer.status == TimerStatus.paused)
            VerticalDivider(
                width: 1,
                thickness: 0.5,
                color: dividerColor),
          _footerBtn(Icons.cancel_outlined, 'Cancel', null,
              () => ref.read(timerListProvider.notifier).cancelTimer(timer.label)),
        ],
      ),
    );
  }

  Widget _footerBtn(
      IconData icon, String label, Color? color, VoidCallback onTap) {
    return Expanded(
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 13),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        style: TextButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: const RoundedRectangleBorder(),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;

  const _ArcPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.progress != progress || old.color != color || old.trackColor != trackColor;
}
