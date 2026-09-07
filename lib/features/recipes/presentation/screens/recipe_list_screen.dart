import 'dart:async';
import 'dart:io' if (dart.library.html) 'package:recipe_app/shared/stubs/io_stub.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/recipe_providers.dart';
import '../widgets/recipe_card.dart';
import '../widgets/markdown_reader.dart';
import '../../data/models/recipe_model.dart';
import 'package:recipe_app/shared/widgets/tag_colors.dart';

class RecipeListScreen extends ConsumerStatefulWidget {
  final String? initialFolder;
  const RecipeListScreen({super.key, this.initialFolder});

  @override
  ConsumerState<RecipeListScreen> createState() => _RecipeListScreenState();
}

class _RecipeListScreenState extends ConsumerState<RecipeListScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.initialFolder != null && widget.initialFolder!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ref.read(currentFolderProvider) != widget.initialFolder) {
          ref.read(currentFolderProvider.notifier).state = widget.initialFolder!;
        }
      });
    }
  }
  RecipeModel? _selectedRecipe;
  final Set<String> _selectedTags = {};

  void _toggleTag(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
    });
  }

  void _clearTags() {
    setState(() => _selectedTags.clear());
  }

  List<RecipeModel> _filterBySearch(List<RecipeModel> recipes, String query) {
    if (query.isEmpty) return recipes;
    final q = query.toLowerCase();
    return recipes.where((r) => r.title.toLowerCase().contains(q)).toList();
  }

  Future<void> _refresh() {
    final folder = ref.read(currentFolderProvider);
    ref.invalidate(recipesInFolderProvider);
    ref.invalidate(subfoldersProvider(folder));
    return Future.value();
  }

  List<RecipeModel> _filterByTags(List<RecipeModel> recipes) {
    if (_selectedTags.isEmpty) return recipes;
    return recipes
        .where((r) => r.tags.any((t) => _selectedTags.contains(t)))
        .toList();
  }

  Set<String> _allTags(List<RecipeModel> recipes) {
    final tags = <String>{};
    for (final r in recipes) {
      tags.addAll(r.tags);
    }
    return tags;
  }

  List<String> _breadcrumbSegments(String folder) {
    if (folder.isEmpty) return [];
    return folder.split('/').where((s) => s.isNotEmpty).toList();
  }

  String _parentPath(String folder) {
    final segs = _breadcrumbSegments(folder);
    if (segs.length <= 1) return '';
    return segs.sublist(0, segs.length - 1).join('/');
  }

  Widget _buildBreadcrumb(BuildContext context, String folder, ThemeData theme) {
    final segs = _breadcrumbSegments(folder);
    if (folder.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.surfaceContainerLowest,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            InkWell(
              onTap: () {
                ref.read(currentFolderProvider.notifier).state = '';
                context.go('/');
              },
              child: Row(children: [
                Icon(Icons.home_outlined, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text('Root', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary)),
              ]),
            ),
            for (int i = 0; i < segs.length; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.chevron_right, size: 16, color: theme.colorScheme.onSurfaceVariant),
              ),
              InkWell(
                onTap: i == segs.length - 1
                    ? null
                    : () {
                        final path = segs.sublist(0, i + 1).join('/');
                        ref.read(currentFolderProvider.notifier).state = path;
                        context.go('/folder/${Uri.encodeComponent(path)}');
                      },
                child: Text(
                  segs[i],
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: i == segs.length - 1 ? theme.colorScheme.onSurface : theme.colorScheme.primary,
                    fontWeight: i == segs.length - 1 ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSubfoldersSection(List<String> subfolders, String folder, ThemeData theme) {
    if (subfolders.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_open, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text('Subfolders', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                tooltip: 'New subfolder',
                onPressed: () => _createSubfolder(context, folder),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...subfolders.map((sf) {
            final fullPath = folder.isEmpty ? sf : '$folder/$sf';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  child: Icon(Icons.folder, color: theme.colorScheme.onSecondaryContainer, size: 18),
                ),
                title: Text(sf, style: theme.textTheme.titleSmall),
                subtitle: Text(fullPath, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
                      tooltip: 'Delete subfolder',
                      onPressed: () => _deleteSubfolder(fullPath, sf),
                    ),
                    Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant, size: 18),
                  ],
                ),
                onTap: () {
                  ref.read(currentFolderProvider.notifier).state = fullPath;
                  context.push('/folder/${Uri.encodeComponent(fullPath)}');
                },
              ),
            );
          }),
          const Divider(height: 16),
        ],
      ),
    );
  }

  Future<void> _createSubfolder(BuildContext context, String parent) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(parent.isEmpty ? 'New Folder' : 'New subfolder in "$parent"'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Folder name', border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    if (name.contains('/') || name.contains('\\')) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Folder name cannot contain / or \\')));
      return;
    }
    final fullPath = parent.isEmpty ? name : '$parent/$name';
    final repo = ref.read(recipeRepositoryProvider).valueOrNull;
    final ok = repo != null ? await repo.createFolder(fullPath) : false;
    ref.invalidate(subfoldersProvider(parent));
    ref.invalidate(foldersProvider);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Create failed — check permissions')));
    }
  }

  Future<void> _deleteSubfolder(String fullPath, String displayName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Folder'),
        content: Text('Delete subfolder "$displayName" and all its recipes?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final repo = ref.read(recipeRepositoryProvider).valueOrNull;
    final ok = repo != null ? await repo.deleteFolder(fullPath) : false;
    final parent = _parentPath(fullPath);
    ref.invalidate(subfoldersProvider(parent));
    ref.invalidate(subfoldersProvider(fullPath));
    ref.invalidate(foldersProvider);
    if (!ok && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delete failed — check permissions')));
  }

  @override
  Widget build(BuildContext context) {
    final folder = ref.watch(currentFolderProvider);
    final recipesAsync = ref.watch(recipesInFolderProvider);
    final subfoldersAsync = ref.watch(subfoldersProvider(folder));
    final recipes = recipesAsync.valueOrNull ?? [];
    final subfolders = subfoldersAsync.valueOrNull ?? [];
    final theme = Theme.of(context);
    final isTablet = MediaQuery.of(context).size.width >= 600;
    final searchQuery = ref.watch(recipeSearchQueryProvider);
    final filtered = _filterByTags(recipes);
    final searched = _filterBySearch(filtered, searchQuery);
    final allTags = _allTags(recipes);

    ref.listen(currentFolderProvider, (prev, next) {
      if (prev != next) {
        ref.read(recipeSearchQueryProvider.notifier).state = '';
        ref.read(debouncedSearchQueryProvider.notifier).state = '';
      }
    });

    final displayFolder = folder.contains('/') ? folder.split('/').last : folder;
    if (isTablet) {
      return Scaffold(
        appBar: AppBar(
          title: Text(displayFolder),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _refresh),
            IconButton(icon: const Icon(Icons.create_new_folder_outlined), tooltip: 'New subfolder', onPressed: () => _createSubfolder(context, folder)),
            IconButton(icon: const Icon(Icons.add), tooltip: 'New recipe', onPressed: () => _createRecipe(context, ref, folder)),
          ],
        ),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 320,
              child: Column(
                children: [
                  _buildBreadcrumb(context, folder, theme),
                  _SearchBarWidget(),
                  _buildSubfoldersSection(subfolders, folder, theme),
                  if (allTags.isNotEmpty) _TagFilterBar(
                    allTags: allTags,
                    selectedTags: _selectedTags,
                    onToggle: _toggleTag,
                    onClear: _selectedTags.isEmpty ? null : _clearTags,
                  ),
                  Expanded(
                    child: recipesAsync.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _buildRecipeList(searched, theme, folder),
                  ),
                ],
              ),
            ),
            VerticalDivider(width: 1, color: theme.colorScheme.outlineVariant),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeInOut,
                switchOutCurve: Curves.easeInOut,
                child: _selectedRecipe != null
                    ? _buildDetailPanel(theme)
                    : _buildPlaceholder(theme),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(displayFolder),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _refresh),
          IconButton(icon: const Icon(Icons.create_new_folder_outlined), tooltip: 'New subfolder', onPressed: () => _createSubfolder(context, folder)),
          IconButton(icon: const Icon(Icons.add), tooltip: 'New recipe', onPressed: () => _createRecipe(context, ref, folder)),
        ],
      ),
      body: Column(
        children: [
          _buildBreadcrumb(context, folder, theme),
          _SearchBarWidget(),
          _buildSubfoldersSection(subfolders, folder, theme),
          if (allTags.isNotEmpty) _TagFilterBar(
            allTags: allTags,
            selectedTags: _selectedTags,
            onToggle: _toggleTag,
            onClear: _selectedTags.isEmpty ? null : _clearTags,
          ),
          Expanded(
            child: recipesAsync.isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildRecipeList(searched, theme, folder),
          ),
        ],
      ),
    );
  }

  Widget _buildRecipeList(
      List<RecipeModel> recipes, ThemeData theme, String folder) {
    if (recipes.isEmpty) {
      return Center(
        child: AnimatedOpacity(
          opacity: 1,
          duration: const Duration(milliseconds: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long,
                  size: 64, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text('No recipes yet', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Add .md files or create one',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _createRecipe(context, ref, folder),
                icon: const Icon(Icons.add),
                label: const Text('New Recipe'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        itemCount: recipes.length,
        itemBuilder: (context, index) {
          final recipe = recipes[index];
          final isTablet = MediaQuery.of(context).size.width >= 600;
                  return RecipeCard(
                    recipe: recipe,
                    dense: isTablet,
                    onTap: () {
                      if (isTablet) {
                        setState(() => _selectedRecipe = recipe);
                      } else {
                        ref.read(currentRecipeProvider.notifier).state = recipe;
                        context.push(
                            '/folder/${Uri.encodeComponent(folder)}/recipe/${Uri.encodeComponent(recipe.fileName)}');
                      }
                    },
                    onDelete: () => _deleteRecipe(context, ref, folder, recipe),
                  );
        },
      ),
    );
  }

  Widget _buildDetailPanel(ThemeData theme) {
    final recipe = _selectedRecipe!;
    final repo = ref.watch(recipeRepositoryProvider).valueOrNull;
    final rootPath = repo?.rootPath ?? '';
    final imageResolver = repo != null
        ? (String folder, String fileName) => repo.imagePathFor(folder, fileName)
        : null;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  recipe.title,
                  style: theme.textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.open_in_full),
                tooltip: 'Open full screen',
                onPressed: () {
                  ref.read(currentRecipeProvider.notifier).state = recipe;
                  context.push(
                    '/folder/${Uri.encodeComponent(recipe.folder)}/recipe/${Uri.encodeComponent(recipe.fileName)}',
                  );
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: MarkdownReader(
            recipe: recipe,
            embedded: true,
            rootPath: rootPath,
            imagePathFor: imageResolver,
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Center(
      child: AnimatedOpacity(
        opacity: 1,
        duration: const Duration(milliseconds: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('Select a recipe', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Choose a recipe from the list to view it here',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteRecipe(BuildContext context, WidgetRef ref, String folder, RecipeModel recipe) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Recipe'),
        content: Text('Delete "${recipe.title}"?'),
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
              final repo = ref.read(recipeRepositoryProvider).valueOrNull;
              final ok = repo != null ? await repo.deleteFile(folder, recipe.fileName) : false;
              if (repo != null && ok && !kIsWeb) {
                for (final img in recipe.images) {
                  if (repo.rootPath != null) {
                    try {
                      final imgFile = File(p.join(repo.rootPath!, folder, img));
                      if (imgFile.existsSync()) imgFile.deleteSync();
                    } catch (_) {}
                  }
                }
              }
              ref.invalidate(recipesInFolderProvider);
              if (ctx.mounted) {
                setState(() {
                  if (_selectedRecipe?.fileName == recipe.fileName) {
                    _selectedRecipe = null;
                  }
                });
                Navigator.pop(ctx);
              }
              if (!ok && ctx.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Delete failed — check folder permissions')),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _createRecipe(BuildContext context, WidgetRef ref, String folder) async {
    final result = await showModalBottomSheet<_FormResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const _NewRecipeSheet(),
    );

    if (result == null) return;

    String _sanitize(String t) {
      var s = t.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '-').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (s.isEmpty) s = 'Untitled';
      if (!s.toLowerCase().endsWith('.md')) s = '$s.md';
      return s;
    }

    final filename = _sanitize(result.title);
    final tags = result.tags.isNotEmpty ? '[${result.tags.join(', ')}]' : '[]';
    final source = result.source.isNotEmpty ? result.source : '';
    final servings = result.servings > 0 ? result.servings : 1;
    final ingredients = result.ingredients.isNotEmpty
        ? result.ingredients
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .map((l) => '- $l')
            .join('\n')
        : '- ';
    final directions = result.directions.isNotEmpty
        ? result.directions
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .map((l) {
              final trimmed = l.trim();
              return RegExp(r'^\d+[\.\)]').hasMatch(trimmed)
                  ? trimmed
                  : '1. $trimmed';
            })
            .join('\n')
        : '1. ';
    String _yamlEsc(String v) => v.contains(':') || v.contains('"') || v.contains("'") || v.contains('#')
        ? '"${v.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"'
        : v;
    final template = '''---
title: ${_yamlEsc(result.title)}
prep_time: ${_yamlEsc(result.prepTime)}
cook_time: ${_yamlEsc(result.cookTime)}
total_time: ${_yamlEsc(result.totalTime)}
servings: $servings
difficulty: ${_yamlEsc(result.difficulty)}
tags: $tags
source: ${_yamlEsc(source)}
---

## Ingredients
$ingredients

## Instructions
$directions

## Notes
''';
    final repo = ref.read(recipeRepositoryProvider).valueOrNull;
    final ok = repo != null ? await repo.writeFile(folder, filename, template) : false;
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create failed — check folder permissions')),
      );
    }
    ref.invalidate(recipesInFolderProvider);
  }
}

class _FormResult {
  final String title;
  final String prepTime;
  final String cookTime;
  final String totalTime;
  final int servings;
  final String difficulty;
  final List<String> tags;
  final String source;
  final String ingredients;
  final String directions;

  _FormResult({
    required this.title,
    this.prepTime = '',
    this.cookTime = '',
    this.totalTime = '',
    this.servings = 1,
    this.difficulty = 'easy',
    this.tags = const [],
    this.source = '',
    this.ingredients = '',
    this.directions = '',
  });
}

class _NewRecipeSheet extends StatefulWidget {
  const _NewRecipeSheet();

  @override
  State<_NewRecipeSheet> createState() => _NewRecipeSheetState();
}

class _NewRecipeSheetState extends State<_NewRecipeSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _prepController = TextEditingController();
  final _cookController = TextEditingController();
  final _totalController = TextEditingController();
  final _servingsController = TextEditingController(text: '1');
  final _tagsController = TextEditingController();
  final _sourceController = TextEditingController();
  final _ingredientsController = TextEditingController();
  final _directionsController = TextEditingController();
  String _difficulty = 'easy';

  @override
  void dispose() {
    _titleController.dispose();
    _prepController.dispose();
    _cookController.dispose();
    _totalController.dispose();
    _servingsController.dispose();
    _tagsController.dispose();
    _sourceController.dispose();
    _ingredientsController.dispose();
    _directionsController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final tags = _tagsController.text
        .split(',')
        .map((t) => t.trim().toLowerCase())
        .where((t) => t.isNotEmpty)
        .toList();
    Navigator.pop(context, _FormResult(
      title: _titleController.text.trim(),
      prepTime: _prepController.text.trim(),
      cookTime: _cookController.text.trim(),
      totalTime: _totalController.text.trim(),
      servings: int.tryParse(_servingsController.text) ?? 1,
      difficulty: _difficulty,
      tags: tags,
      source: _sourceController.text.trim(),
      ingredients: _ingredientsController.text.trim(),
      directions: _directionsController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 12, 24, 12 + bottomInset),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 32, height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('New Recipe', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 20),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Recipe name', hintText: 'e.g. Spaghetti Carbonara'),
                textCapitalization: TextCapitalization.words,
                autofocus: true,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: TextFormField(
                    controller: _prepController,
                    decoration: const InputDecoration(labelText: 'Prep time', hintText: '15 min'),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(
                    controller: _cookController,
                    decoration: const InputDecoration(labelText: 'Cook time', hintText: '30 min'),
                  )),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: TextFormField(
                    controller: _totalController,
                    decoration: const InputDecoration(labelText: 'Total time', hintText: '45 min'),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(
                    controller: _servingsController,
                    decoration: const InputDecoration(labelText: 'Servings'),
                    keyboardType: TextInputType.number,
                  )),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _difficulty,
                decoration: const InputDecoration(labelText: 'Difficulty'),
                items: ['easy', 'medium', 'hard']
                    .map((d) => DropdownMenuItem(value: d, child: Text(d[0].toUpperCase() + d.substring(1))))
                    .toList(),
                onChanged: (v) => setState(() => _difficulty = v ?? 'easy'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _tagsController,
                decoration: const InputDecoration(labelText: 'Tags', hintText: 'italian, pasta, dinner'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _ingredientsController,
                decoration: const InputDecoration(
                  labelText: 'Ingredients',
                  hintText: '200g pasta\n2 eggs\n...',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _directionsController,
                decoration: const InputDecoration(
                  labelText: 'Directions',
                  hintText: 'Boil water\nCook pasta\n...',
                ),
                maxLines: 4,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _sourceController,
                decoration: const InputDecoration(labelText: 'Source URL', hintText: 'https://...'),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.add),
                  label: const Text('Create Recipe'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBarWidget extends ConsumerStatefulWidget {
  const _SearchBarWidget();

  @override
  ConsumerState<_SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends ConsumerState<_SearchBarWidget> {
  Timer? _debounce;
  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    ref.read(recipeSearchQueryProvider.notifier).state = v;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) ref.read(debouncedSearchQueryProvider.notifier).state = v;
    });
  }

  void _clear() {
    _debounce?.cancel();
    ref.read(recipeSearchQueryProvider.notifier).state = '';
    ref.read(debouncedSearchQueryProvider.notifier).state = '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searchQuery = ref.watch(recipeSearchQueryProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        onChanged: _onChanged,
        decoration: InputDecoration(
          hintText: 'Search recipes...',
          prefixIcon: Icon(Icons.search, color: theme.colorScheme.onSurfaceVariant),
          suffixIcon: searchQuery.isNotEmpty
              ? IconButton(icon: const Icon(Icons.clear), onPressed: _clear)
              : null,
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _TagFilterBar extends StatelessWidget {
  final Set<String> allTags;
  final Set<String> selectedTags;
  final ValueChanged<String> onToggle;
  final VoidCallback? onClear;

  const _TagFilterBar({
    required this.allTags,
    required this.selectedTags,
    required this.onToggle,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final tagsList = allTags.toList()..sort();
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            if (onClear != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: onClear,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.clear_all, size: 14, color: theme.colorScheme.onErrorContainer),
                        const SizedBox(width: 4),
                        Text('Clear', style: TextStyle(color: theme.colorScheme.onErrorContainer, fontWeight: FontWeight.w600, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
            ...tagsList.map((tag) {
              final selected = selectedTags.contains(tag);
              final c = tagColor(tag, theme.colorScheme);
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => onToggle(tag),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: selected ? c.withValues(alpha: 0.25) : c.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? c : c.withValues(alpha: 0.3),
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tag, size: 13, color: c),
                        const SizedBox(width: 4),
                        Text(tag, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
