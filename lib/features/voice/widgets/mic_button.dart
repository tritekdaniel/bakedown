import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../voice_providers.dart';

class MicButton extends ConsumerWidget {
  final VoidCallback onToggle;

  const MicButton({super.key, required this.onToggle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(voiceEnabledProvider);
    if (!enabled) return const SizedBox.shrink();

    final isListening = ref.watch(voiceListeningProvider);
    final voiceState = ref.watch(voiceStateProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final active = isListening && voiceState != VoiceState.idle;

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: SizedBox(
        width: 36,
        height: 36,
        child: Material(
          color: active
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
          elevation: active ? 2 : 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onToggle,
            child: Icon(
              active ? Icons.mic : Icons.mic_none,
              size: 18,
              color: active
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class ListeningIndicator extends StatelessWidget {
  const ListeningIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: colorScheme.onPrimaryContainer,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'Listening',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
