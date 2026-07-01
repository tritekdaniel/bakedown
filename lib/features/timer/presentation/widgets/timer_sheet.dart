import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_app/core/theme/app_spacing.dart';
import 'package:recipe_app/features/timer/presentation/providers/timer_providers.dart';
import 'package:recipe_app/features/timer/presentation/widgets/add_timer_modal.dart';
import 'package:recipe_app/features/timer/presentation/widgets/timer_tile.dart';

class TimerSheet extends ConsumerWidget {
  const TimerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeTimersProvider);
    final completed = ref.watch(completedTimersProvider);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Timers', style: theme.textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add timer',
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const AddTimerModal(),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (active.isEmpty && completed.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(
                  child: Text(
                    'No timers yet.\nSay "set timer 5 minutes" or tap +.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            if (active.isNotEmpty) ...[
              Text('Active', style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              ...active.map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: TimerTile(timer: t),
                  )),
            ],
            if (completed.isNotEmpty) ...[
              if (active.isNotEmpty) const SizedBox(height: AppSpacing.md),
              Text('Completed', style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              ...completed.map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: TimerTile(timer: t),
                  )),
            ],
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }
}
