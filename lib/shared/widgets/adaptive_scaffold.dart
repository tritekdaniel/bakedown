import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_app/core/theme/app_spacing.dart';
import 'package:recipe_app/features/settings/presentation/providers/settings_providers.dart';
import 'package:recipe_app/features/timer/presentation/providers/timer_providers.dart';
import 'package:recipe_app/features/timer/presentation/widgets/timer_sheet.dart';
import 'package:recipe_app/features/tts/presentation/widgets/reading_controls.dart';
import 'package:recipe_app/features/voice/voice_providers.dart';
import 'package:recipe_app/features/voice/widgets/mic_button.dart';
import '../../core/theme/app_breakpoints.dart';
import '../../features/recipes/presentation/providers/recipe_providers.dart';

int _uiToBranch(bool showFormat, int uiIndex) {
  if (showFormat) return uiIndex;
  return uiIndex >= 1 ? uiIndex + 1 : uiIndex;
}

int _branchToUi(bool showFormat, int branchIndex) {
  if (showFormat) return branchIndex;
  return branchIndex > 0 ? branchIndex - 1 : branchIndex;
}

class AdaptiveScaffold extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const AdaptiveScaffold({super.key, required this.navigationShell});

  void _onDestinationSelected(WidgetRef ref, int uiIndex) {
    final showFormat = ref.read(settingsProvider).aiEnabled;
    final branchIndex = _uiToBranch(showFormat, uiIndex);
    navigationShell.goBranch(
      branchIndex,
      initialLocation: branchIndex == navigationShell.currentIndex,
    );
    if (branchIndex == 0) {
      ref.read(refreshCounterProvider.notifier).state++;
    }
  }

  void _toggleMic(WidgetRef ref) {
    final isListening = ref.read(voiceListeningProvider);
    ref.read(voiceListeningProvider.notifier).state = !isListening;
  }

  void _openTimerSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => const TimerSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final showFormat = ref.watch(settingsProvider).aiEnabled;
    final uiIndex = _branchToUi(showFormat, navigationShell.currentIndex);
    final activeTimers = ref.watch(activeTimersProvider);

    final navDestinations = [
      NavigationDestination(
        icon: Icon(Icons.menu_book_outlined),
        selectedIcon: Icon(Icons.menu_book),
        label: 'Browse',
      ),
      if (showFormat)
        NavigationDestination(
          icon: Icon(Icons.auto_awesome_outlined),
          selectedIcon: Icon(Icons.auto_awesome),
          label: 'Format',
        ),
      NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: 'Settings',
      ),
    ];

    final railDestinations = [
      NavigationRailDestination(
        icon: Icon(Icons.menu_book_outlined),
        selectedIcon: Icon(Icons.menu_book),
        label: Text('Browse'),
      ),
      if (showFormat)
        NavigationRailDestination(
          icon: Icon(Icons.auto_awesome_outlined),
          selectedIcon: Icon(Icons.auto_awesome),
          label: Text('Format'),
        ),
      NavigationRailDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: Text('Settings'),
      ),
    ];

    if (AppBreakpoints.isDesktop(width)) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: uiIndex,
              onDestinationSelected: (i) => _onDestinationSelected(ref, i),
              labelType: NavigationRailLabelType.all,
              groupAlignment: 0,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Icon(
                  Icons.restaurant_menu,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
              ),
              trailing: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (activeTimers.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: _TimerBadge(
                          count: activeTimers.length,
                          onTap: () => _openTimerSheet(context),
                        ),
                      ),
                    MicButton(onToggle: () => _toggleMic(ref)),
                  ],
                ),
              ),
              destinations: railDestinations,
            ),
            VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: navigationShell),
                  const ReadingControls(),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ReadingControls(),
          NavigationBar(
            selectedIndex: uiIndex,
            onDestinationSelected: (i) => _onDestinationSelected(ref, i),
            destinations: navDestinations,
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (activeTimers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: FloatingActionButton.small(
                heroTag: 'timer',
                onPressed: () => _openTimerSheet(context),
                child: Badge(
                  label: Text('${activeTimers.length}'),
                  child: const Icon(Icons.timer_outlined),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 56),
            child: MicButton(onToggle: () => _toggleMic(ref)),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

class _TimerBadge extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _TimerBadge({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.secondaryContainer,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Badge(
            label: Text('$count'),
            isLabelVisible: count > 0,
            child: Icon(
              Icons.timer_outlined,
              color: theme.colorScheme.onSecondaryContainer,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
