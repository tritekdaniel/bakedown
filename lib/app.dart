import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'features/recipes/presentation/screens/folder_browser_screen.dart';
import 'features/recipes/presentation/screens/recipe_list_screen.dart';
import 'features/recipes/presentation/screens/recipe_screen.dart';
import 'features/ai_transcoder/presentation/screens/ai_transcode_screen.dart';
import 'features/settings/presentation/screens/settings_screen.dart';
import 'features/settings/presentation/providers/settings_providers.dart';
import 'features/voice/voice_dispatcher.dart';
import 'core/theme/app_theme.dart';
import 'shared/widgets/adaptive_scaffold.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AdaptiveScaffold(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                pageBuilder: (context, state) => CustomTransitionPage(
                  key: state.pageKey,
                  child: const FolderBrowserScreen(),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    return FadeThroughTransition(
                      animation: animation,
                      secondaryAnimation: secondaryAnimation,
                      child: child,
                    );
                  },
                ),
                routes: [
                  GoRoute(
                    path: 'folder/:folder',
                    pageBuilder: (context, state) => CustomTransitionPage(
                      key: state.pageKey,
                      child: RecipeListScreen(
                        initialFolder: Uri.decodeComponent(state.pathParameters['folder']!),
                      ),
                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                        return SharedAxisTransition(
                          animation: animation,
                          secondaryAnimation: secondaryAnimation,
                          transitionType: SharedAxisTransitionType.vertical,
                          child: child,
                        );
                      },
                    ),
                    routes: [
                      GoRoute(
                        path: 'recipe/:filename',
                        pageBuilder: (context, state) => CustomTransitionPage(
                          key: state.pageKey,
                          child: RecipeScreen(
                            folder: Uri.decodeComponent(state.pathParameters['folder']!),
                            filename: Uri.decodeComponent(state.pathParameters['filename']!),
                          ),
                          transitionsBuilder: (context, animation, secondaryAnimation, child) {
                            return SharedAxisTransition(
                              animation: animation,
                              secondaryAnimation: secondaryAnimation,
                              transitionType: SharedAxisTransitionType.horizontal,
                              fillColor: Theme.of(context).colorScheme.surface,
                              child: child,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/transcode',
                pageBuilder: (context, state) => CustomTransitionPage(
                  key: state.pageKey,
                  child: AITranscodeScreen(
                    initialText: state.extra as String?,
                  ),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    return FadeThroughTransition(
                      animation: animation,
                      secondaryAnimation: secondaryAnimation,
                      child: child,
                    );
                  },
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                pageBuilder: (context, state) => CustomTransitionPage(
                  key: state.pageKey,
                  child: const SettingsScreen(),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    return FadeThroughTransition(
                      animation: animation,
                      secondaryAnimation: secondaryAnimation,
                      child: child,
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class RecipeApp extends ConsumerWidget {
  const RecipeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final darkMode = ref.watch(settingsProvider.select((s) => s.darkMode));
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: 'Bakedown',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
      builder: (context, child) => VoiceDispatcher(child: child!),
      debugShowCheckedModeBanner: false,
    );
  }
}
