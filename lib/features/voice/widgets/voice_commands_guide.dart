import 'package:flutter/material.dart';

class VoiceCommandsGuide extends StatelessWidget {
  const VoiceCommandsGuide({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Voice Commands', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Tap the mic button on any screen, then speak a command.',
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            _Group(
              icon: Icons.navigation,
              label: 'Navigation',
              commands: const [
                ('Go home', '"home" "show my recipes" "go back to folders"'),
                ('Go to settings', '"settings" "open settings"'),
                ('Go to transcode', '"transcode" "new recipe" "import"'),
                ('Go back', '"back" "go back" "return"'),
              ],
            ),
            _Group(
              icon: Icons.menu_book,
              label: 'Recipe',
              commands: const [
                ('Open recipe', '"open banana bread" "show chocolate cake"'),
                ('Switch to Ingredients', '"ingredients" "show ingredients"'),
                ('Switch to Editor', '"editor" "edit mode"'),
              ],
            ),
            _Group(
              icon: Icons.straighten,
              label: 'Scaling',
              commands: const [
                ('Double', '"double" "double it" "scale to 2"'),
                ('Triple', '"triple" "triple the recipe"'),
                ('Halve', '"halve it" "half the recipe"'),
                ('Custom', '"scale to 3" "scale to 1.5"'),
              ],
            ),
            _Group(
              icon: Icons.swap_horiz,
              label: 'Unit Conversion',
              commands: const [
                ('To grams', '"convert to grams" "use grams"'),
                ('To cups', '"convert to cups" "use cups"'),
                ('To ounces', '"convert to ounces" "change to ounces"'),
                ('To milliliters', '"switch to milliliters" "use milliliters"'),
              ],
            ),
            _Group(
              icon: Icons.timer_outlined,
              label: 'Timers',
              commands: const [
                ('Set timer', '"set timer for 5 minutes" "10 minute timer"'),
                ('Cancel timer', '"cancel timer" "stop timer"'),
                ('Pause/Resume', '"pause timer" "resume timer"'),
                ('Time left', '"how much time left" "time remaining"'),
              ],
            ),
            _Group(
              icon: Icons.record_voice_over_outlined,
              label: 'Reading (TTS)',
              commands: const [
                ('Read ingredients', '"read ingredients" "read"'),
                ('Read instructions', '"read instructions" "read steps"'),
                ('Read a step', '"read step 3"'),
                ('Next / Previous', '"next" "previous"'),
                ('Stop / Pause', '"stop reading" "pause reading"'),
                ('Resume', '"resume" "keep going"'),
              ],
            ),
            const SizedBox(height: 8),
            Divider(color: cs.outlineVariant),
            const SizedBox(height: 8),
            Text(
              'Tips',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _Tip(text: 'Enable "Require Hey Recipe prefix" in settings to reduce false triggers.'),
            _Tip(text: 'Say "stop listening" or tap the mic button to turn off the mic.'),
            _Tip(text: 'Recipe names use fuzzy matching — minor typos are OK.'),
            _Tip(text: 'Say "how much time left" while a timer is running to hear the countdown.'),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<(String, String)> commands;

  const _Group({
    required this.icon,
    required this.label,
    required this.commands,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(label, style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.primary,
              )),
            ],
          ),
          const SizedBox(height: 8),
          ...commands.map((c) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 100,
                  child: Text(c.$1,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(c.$2,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  final String text;
  const _Tip({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          )),
          Expanded(
            child: Text(text, style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
          ),
        ],
      ),
    );
  }
}

void showVoiceCommandsGuide(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const VoiceCommandsGuide(),
  );
}
