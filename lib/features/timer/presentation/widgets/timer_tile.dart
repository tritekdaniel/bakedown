import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_app/core/theme/app_spacing.dart';
import 'package:recipe_app/features/timer/domain/models/timer_model.dart';
import 'package:recipe_app/features/timer/presentation/providers/timer_providers.dart';

class TimerTile extends ConsumerWidget {
  final TimerModel timer;

  const TimerTile({super.key, required this.timer});

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
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(timerListProvider.notifier);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: timer.progress,
                    strokeWidth: 3,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                  Icon(
                    timer.status == TimerStatus.completed
                        ? Icons.check_circle
                        : timer.status == TimerStatus.paused
                            ? Icons.pause_circle
                            : Icons.timer,
                    size: 20,
                    color: timer.status == TimerStatus.completed
                        ? theme.colorScheme.primary
                        : timer.status == TimerStatus.paused
                            ? theme.colorScheme.tertiary
                            : theme.colorScheme.secondary,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(timer.label, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    _formatDuration(timer.remaining),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    soundDisplayName(timer.soundFile),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (timer.status == TimerStatus.running)
              IconButton(
                icon: const Icon(Icons.pause),
                onPressed: () => notifier.pauseTimer(timer.label),
              ),
            if (timer.status == TimerStatus.paused)
              IconButton(
                icon: const Icon(Icons.play_arrow),
                onPressed: () => notifier.resumeTimer(timer.label),
              ),
            if (timer.isAlarming)
              IconButton(
                icon: const Icon(Icons.alarm_off),
                tooltip: 'Dismiss alarm',
                onPressed: () => notifier.dismissAlarm(timer.id),
              ),
            if (timer.status == TimerStatus.completed && !timer.isAlarming)
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => notifier.dismissCompleted(timer.id),
              )
            else if (timer.status != TimerStatus.completed)
              IconButton(
                icon: const Icon(Icons.cancel_outlined),
                onPressed: () => notifier.cancelTimer(timer.label),
              ),
          ],
        ),
      ),
    );
  }
}
