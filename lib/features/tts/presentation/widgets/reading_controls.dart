import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_app/core/theme/app_spacing.dart';
import 'package:recipe_app/features/tts/domain/models/tts_service.dart';
import 'package:recipe_app/features/tts/presentation/providers/tts_providers.dart';

class ReadingControls extends ConsumerWidget {
  const ReadingControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ttsStateProvider);
    final notifier = ref.read(ttsStateProvider.notifier);
    final theme = Theme.of(context);

    if (!state.isActive) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.currentPhrase,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${state.currentIndex + 1} / ${state.phrases.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _IconButton(
              icon: Icons.skip_previous,
              onPressed: state.currentIndex > 0 ? () => notifier.previous() : null,
            ),
            const SizedBox(width: AppSpacing.xs),
            _IconButton(
              icon: state.status == TtsStatus.paused ? Icons.play_arrow : Icons.pause,
              onPressed: state.status == TtsStatus.paused
                  ? () => notifier.resume()
                  : () => notifier.pause(),
            ),
            const SizedBox(width: AppSpacing.xs),
            _IconButton(
              icon: Icons.skip_next,
              onPressed: state.currentIndex < state.phrases.length - 1
                  ? () => notifier.next()
                  : null,
            ),
            const SizedBox(width: AppSpacing.xs),
            _IconButton(
              icon: Icons.close,
              onPressed: () => notifier.stop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _IconButton({required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 20,
            color: enabled
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurface.withValues(alpha: 0.38),
          ),
        ),
      ),
    );
  }
}
