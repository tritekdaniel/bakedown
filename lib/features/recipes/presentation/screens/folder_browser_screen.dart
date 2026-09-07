import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/utils/android_saf_helper.dart';
import '../../../../shared/utils/web_fs_helper.dart';
import 'package:recipe_app/shared/widgets/file_browser.dart';
import 'package:recipe_app/features/settings/domain/models/app_settings.dart';
import 'package:recipe_app/features/settings/presentation/providers/settings_providers.dart';
import '../../data/repositories/recipe_repository.dart';
import '../../data/models/recipe_model.dart';
import '../providers/recipe_providers.dart';

class FolderBrowserScreen extends ConsumerStatefulWidget {
  const FolderBrowserScreen({super.key});

  @override
  ConsumerState<FolderBrowserScreen> createState() => _FolderBrowserScreenState();
}

class _FolderBrowserScreenState extends ConsumerState<FolderBrowserScreen> {
  late final TextEditingController _searchController;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: ref.read(recipeSearchQueryProvider));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    ref.read(recipeSearchQueryProvider.notifier).state = v;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) ref.read(debouncedSearchQueryProvider.notifier).state = v;
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    ref.read(recipeSearchQueryProvider.notifier).state = '';
    ref.read(debouncedSearchQueryProvider.notifier).state = '';
  }
  Future<void> _pickDirectory() async {
    if (kIsWeb) {
      if (isFileSystemAccessSupported) {
        final handle = await WebFsHelper.pickDirectory();
        if (handle == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No folder selected or browser denied access')),
          );
          return;
        }
        ref.read(webFsHandleRevisionProvider.notifier).state++;
        ref.invalidate(recipeRepositoryProvider);
        ref.invalidate(foldersProvider);
        await ref.read(settingsProvider.notifier).updateDirectory(WebFsHelper.rootName ?? 'web-fs');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Using folder: ${WebFsHelper.rootName}')),
          );
        }
        return;
      }
      _showManualPathDialog();
      return;
    }

    final initial = ref.read(settingsProvider).recipeDirectory;

    final isContentUri = initial.startsWith('content://');
    String? result;
    try {
      result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Recipe Folder',
        initialDirectory: initial.isEmpty || isContentUri ? null : initial,
        lockParentWindow: true,
      );
    } catch (e) {
      debugPrint('[PICKER] FilePicker failed: $e — falling back to in-app browser');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('System picker failed ($e) — trying in-app browser')),
      );
      final fallback = await showFolderBrowser(context, initialPath: initial);
      if (fallback == null || fallback == '__native__') return;
      result = fallback;
    }
    if (result == null) {
      // FilePicker returns null on cancel — offer in-app fallback on Linux where zenity/kdialog may be missing
      if (!mounted) return;
      // Don't auto-fallback on cancel, but if on Linux and picker silently fails, let user try in-app
      if (defaultTargetPlatform == TargetPlatform.linux) {
        final tryInApp = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('System picker unavailable'),
            content: const Text('Install zenity (sudo apt install zenity) or use in-app browser.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open In-App Browser')),
            ],
          ),
        );
        if (tryInApp == true) {
          final fallback = await showFolderBrowser(context, initialPath: initial);
          if (fallback == null || fallback == '__native__') return;
          result = fallback;
        } else {
          return;
        }
      } else {
        return;
      }
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android &&
        result.startsWith('content://')) {
      await AndroidSafHelper.takePersistablePermission(result);
      await AndroidSafHelper.listFiles(result);
    }

    await ref.read(settingsProvider.notifier).updateDirectory(result);
  }

  void _showManualPathDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recipe Directory Path'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter the absolute path to your recipe folder:'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '/path/to/recipes',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final path = controller.text.trim();
              if (path.isNotEmpty) {
                ref.read(settingsProvider.notifier).updateDirectory(path);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Set Path'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final foldersAsync = ref.watch(foldersProvider);
    final repoAsync = ref.watch(recipeRepositoryProvider);
    final repo = repoAsync.valueOrNull;
    final folders = foldersAsync.valueOrNull ?? [];
    final theme = Theme.of(context);
    final isLoading = repoAsync.isLoading || foldersAsync.isLoading;

    Future<void> refresh() {
      ref.invalidate(foldersProvider);
      return Future.value();
    }

    final settingsLoaded = ref.watch(settingsLoadedProvider);
    if (!settingsLoaded) {
      return Scaffold(
        appBar: AppBar(title: const Text(AppConstants.appTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (kIsWeb && isFileSystemAccessSupported && !WebFsHelper.hasHandle) {
      return Scaffold(
        appBar: AppBar(title: const Text(AppConstants.appTitle)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_open, size: 80, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('Choose a folder on disk',
                  style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Pick a real folder via Chrome/Edge File System Access\n(files are stored on disk, not in browser storage)',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _pickDirectory,
                icon: const Icon(Icons.folder_open),
                label: const Text('Pick Folder on Disk'),
              ),
              const SizedBox(height: 8),
              Text(
                'Requires Chrome/Edge on localhost or HTTPS',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    if (!kIsWeb && !settings.smbEnabled && settings.recipeDirectory.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text(AppConstants.appTitle)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book, size: 80, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('Choose your recipe folder',
                  style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Recipes are stored as .md files in subfolders',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _pickDirectory,
                icon: const Icon(Icons.folder_open),
                label: const Text('Select Folder'),
              ),
            ],
          ),
        ),
      );
    }

    final searchQuery = ref.watch(recipeSearchQueryProvider);
    final filteredAsync = ref.watch(filteredRecipesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appTitle),
        actions: [
          if (searchQuery.isEmpty) ...[
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: refresh,
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'New folder',
              onPressed: () => _createFolder(context),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search recipes across all folders...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: _clearSearch,
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                isDense: true,
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(
            child: searchQuery.isNotEmpty
                ? _buildSearchResults(filteredAsync, theme)
                : _buildFolderList(
                    isLoading, repo, settings, folders, theme, refresh),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(
      AsyncValue<List<RecipeModel>> asyncRecipes, ThemeData theme) {
    return asyncRecipes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Search failed: $e')),
      data: (recipes) {
        if (recipes.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_off, size: 64,
                    color: theme.colorScheme.outline),
                const SizedBox(height: 16),
                Text('No recipes match your search',
                    style: theme.textTheme.titleMedium),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: recipes.length,
          itemBuilder: (context, index) {
            final r = recipes[index];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(Icons.menu_book,
                      color: theme.colorScheme.onPrimaryContainer),
                ),
                title: Text(r.title),
                subtitle: Text(r.folder,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
                trailing: Icon(Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant),
                onTap: () {
                  ref.read(currentFolderProvider.notifier).state = r.folder;
                  context.push('/folder/${Uri.encodeComponent(r.folder)}');
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _resetSettings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset settings?'),
        content: const Text('This clears the saved folder, network share and bridge config (fixes bad config). You can re-select your folder after.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(settingsProvider.notifier).resetAll();
    ref.invalidate(recipeRepositoryProvider);
    ref.invalidate(foldersProvider);
    ref.read(currentFolderProvider.notifier).state = '';
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings reset — pick your folder again')));
  }

  Widget _buildFolderList(bool isLoading, RecipeRepository? repo,
      AppSettings settings, List<String> folders, ThemeData theme,
      Future<void> Function() refresh) {
    if (isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Loading folders…', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: _resetSettings,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Frozen? Reset settings'),
            ),
            const SizedBox(height: 8),
            Text('Bad config from a previous build can freeze on launch',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }
    if (repo == null) {
      return Center(
        child: settings.smbEnabled
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off, size: 64,
                      color: theme.colorScheme.error),
                  const SizedBox(height: 16),
                  Text('Could not connect to network share',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Check settings or try again',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/settings'),
                    icon: const Icon(Icons.settings),
                    label: const Text('Open Settings'),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _resetSettings,
                    icon: const Icon(Icons.restart_alt, size: 16),
                    label: const Text('Reset settings'),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_off, size: 64,
                      color: theme.colorScheme.error),
                  const SizedBox(height: 16),
                  Text('Could not access recipe folder',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    settings.recipeDirectory.isNotEmpty
                        ? 'Path: ${settings.recipeDirectory}'
                        : 'No folder selected',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _pickDirectory,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Reselect Folder'),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _resetSettings,
                    icon: const Icon(Icons.restart_alt, size: 16),
                    label: const Text('Reset settings'),
                  ),
                ],
              ),
      );
    }
    if (folders.isEmpty) {
      return RefreshIndicator(
        onRefresh: refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: Center(
              child: AnimatedOpacity(
                opacity: 1,
                duration: const Duration(milliseconds: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_off,
                        size: 64,
                        color: theme.colorScheme.outline),
                    const SizedBox(height: 16),
                    Text('No recipe folders yet',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      settings.smbEnabled
                          ? 'Add subfolders to "${settings.smbHost}\\${settings.smbShare}"'
                          : 'Create subfolders in "${settings.recipeDirectory}"',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _createFolder(context),
                      icon: const Icon(Icons.create_new_folder),
                      label: const Text('Create Folder'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: folders.length,
        itemBuilder: (context, index) {
          final folder = folders[index];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    theme.colorScheme.primaryContainer,
                child: Icon(Icons.folder,
                    color:
                        theme.colorScheme.onPrimaryContainer),
              ),
              title: Text(folder),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        size: 20,
                        color: theme.colorScheme.error),
                    constraints: const BoxConstraints(
                        minWidth: 24, minHeight: 24),
                    onPressed: () => _deleteFolder(folder),
                  ),
                  Icon(Icons.chevron_right,
                      color: theme
                          .colorScheme.onSurfaceVariant),
                ],
              ),
              onTap: () {
                ref
                    .read(currentFolderProvider.notifier)
                    .state = folder;
                context.push('/folder/${Uri.encodeComponent(folder)}');
              },
            ),
          );
        },
      ),
    );
  }

  void _deleteFolder(String folderName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Folder'),
        content: Text('Delete folder "$folderName" and all its recipes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              final repo =
                  ref.read(recipeRepositoryProvider).valueOrNull;
              final ok = repo != null ? await repo.deleteFolder(folderName) : false;
              ref.invalidate(foldersProvider);
              if (ctx.mounted) Navigator.pop(ctx);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'Delete failed — check folder permissions')),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _createFolder(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Folder name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final repo =
                    ref.read(recipeRepositoryProvider).valueOrNull;
                final ok = repo != null
                    ? await repo.createFolder(controller.text)
                    : false;
                ref.invalidate(foldersProvider);
                if (ctx.mounted) Navigator.pop(ctx);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Create failed — check folder permissions')),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
