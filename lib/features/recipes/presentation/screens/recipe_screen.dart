import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_app/core/theme/app_radius.dart';
import 'package:recipe_app/core/theme/app_spacing.dart';
import 'package:recipe_app/features/ai_transcoder/presentation/providers/ai_providers.dart';
import 'package:recipe_app/features/settings/presentation/providers/settings_providers.dart';
import 'package:recipe_app/features/timer/presentation/widgets/add_timer_modal.dart';
import 'package:recipe_app/features/voice/voice_command.dart';
import 'package:recipe_app/features/voice/voice_providers.dart';
import '../providers/recipe_providers.dart';
import '../widgets/markdown_reader.dart';
import '../widgets/markdown_editor.dart';
import '../widgets/scale_selector.dart';
import '../../data/models/recipe_model.dart';
import '../../data/services/ingredient_parser.dart';

class RecipeScreen extends ConsumerStatefulWidget {
  final String folder;
  final String filename;

  const RecipeScreen({
    super.key,
    required this.folder,
    required this.filename,
  });

  @override
  ConsumerState<RecipeScreen> createState() => _RecipeScreenState();
}

class _RecipeScreenState extends ConsumerState<RecipeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRecipe();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRecipe() async {
    _clearSession();
    final repo = ref.read(recipeRepositoryProvider).valueOrNull;
    if (repo == null) {
      ref.read(currentRecipeProvider.notifier).state = null;
      return;
    }
    final content = await repo.readFile(widget.folder, widget.filename);
    if (content != null) {
      final recipe = RecipeModel.fromMarkdown(
        content,
        fileName: widget.filename,
        folder: widget.folder,
      );
      ref.read(currentRecipeProvider.notifier).state = recipe;
      ref.read(recipeContentProvider.notifier).state = content;
    } else {
      ref.read(currentRecipeProvider.notifier).state = null;
    }
  }

  Future<void> _saveRecipe() async {
    final content = ref.read(recipeContentProvider);
    final repo = ref.read(recipeRepositoryProvider).valueOrNull;
    if (repo == null || content.isEmpty) return;
    final ok = await repo.writeFile(widget.folder, widget.filename, content);
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Save failed — check folder permissions')),
        );
      }
      return;
    }
    await _loadRecipe();
    ref.invalidate(recipesInFolderProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _saveWithEdits() async {
    final content = ref.read(recipeContentProvider);
    final edits = ref.read(memoryEditsProvider);
    final factor = ref.read(scaleFactorProvider);
    final checkboxRe = RegExp(r'^(- \[[ xX]\] )(.*)$');

    final lines = content.split('\n');
    final updated = lines.map((line) {
      final m = checkboxRe.firstMatch(line);
      if (m == null) return line;
      final text = m.group(2)!.trim();

      if (edits.containsKey(text)) {
        return '${m.group(1)}${edits[text]}';
      }

      if (factor != 1.0) {
        final scaled = IngredientParser.scaleLine(line, factor);
        if (scaled != null) return scaled;
      }

      return line;
    }).join('\n');

    ref.read(recipeContentProvider.notifier).state = updated;
    _resetEdits();
    await _saveRecipe();
  }

  void _resetEdits() {
    ref.read(scaleFactorProvider.notifier).state = 1.0;
    ref.read(memoryEditsProvider.notifier).clearAll();
  }

  void _toggleCheckbox([int index = 0]) {
    final content = ref.read(recipeContentProvider);
    if (content.isEmpty) return;
    final lines = content.split('\n');
    final checkboxRe = RegExp(r'^- \[([ xX])\] ');
    var found = 0;
    for (var i = 0; i < lines.length; i++) {
      final m = checkboxRe.firstMatch(lines[i]);
      if (m == null) continue;
      if (found < index) {
        found++;
        continue;
      }
      final checked = m.group(1) == 'x';
      lines[i] = lines[i].replaceFirst(
        checked ? '[x]' : '[ ]',
        checked ? '[ ]' : '[x]',
      );
      ref.read(recipeContentProvider.notifier).state = lines.join('\n');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(checked ? 'Unchecked item' : 'Checked item'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No checkboxes found'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _clearSession() {
    _resetEdits();
    ref.read(unitConversionProvider.notifier).clearAll();
  }

  void _navigateBack() {
    _clearSession();
    ref.read(currentRecipeProvider.notifier).state = null;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final recipe = ref.watch(currentRecipeProvider);
    final settings = ref.watch(settingsProvider);
    final repo = ref.read(recipeRepositoryProvider).valueOrNull;
    final rootPath = repo?.rootPath ?? '';
    final imageResolver = repo != null
        ? (String folder, String fileName) => repo.imagePathFor(folder, fileName)
        : null;
    final scaleFactor = ref.watch(scaleFactorProvider);
    final memoryEdits = ref.watch(memoryEditsProvider);
    final hasActiveEdits = scaleFactor != 1.0 || memoryEdits.isNotEmpty;

    ref.listen(recipeRepositoryProvider, (prev, next) {
      if (prev?.valueOrNull == null && next.valueOrNull != null && recipe == null) {
        _loadRecipe();
      }
    });

    ref.listen<double>(scaleFactorProvider, (prev, next) {
      if (prev != null && prev != next) {
        ref.read(memoryEditsProvider.notifier).clearAll();
      }
    });

    ref.listen<VoiceCommand?>(voiceCommandProvider, (prev, next) {
      if (next == null) return;
      switch (next) {
        case SwitchTab(:final index):
          if (index >= 0 && index < _tabController.length) {
            _tabController.animateTo(index);
          }
          ref.read(voiceCommandProvider.notifier).state = null;
        case ConvertUnit(:final unit):
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Convert to $unit — tap highlighted ingredients'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
          ref.read(voiceCommandProvider.notifier).state = null;
        case ToggleCheckbox(:final index):
          _toggleCheckbox(index);
          ref.read(voiceCommandProvider.notifier).state = null;
        case _:
          break;
      }
    });

    if (recipe == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Recipe not found')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 64, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text('Could not load recipe',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('The file may have been moved or deleted',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(recipe.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _navigateBack,
        ),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Save',
              onPressed: _saveRecipe,
            ),
          if (!_isEditing)
            IconButton(
              icon: Icon(hasActiveEdits ? Icons.undo : Icons.straighten),
              tooltip: hasActiveEdits
                  ? 'Revert edits'
                  : 'Scale (${_factorLabel(scaleFactor)})',
              onPressed: hasActiveEdits
                  ? _resetEdits
                  : () => ScaleSelector.show(
                      context,
                      currentFactor: scaleFactor,
                      onSelected: (f) {
                        ref.read(scaleFactorProvider.notifier).state = f;
                      },
                    ),
            ),
          if (scaleFactor != 1.0)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xxs),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  _factorLabel(scaleFactor),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onTertiaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          if (hasActiveEdits)
            IconButton(
              icon: Icon(Icons.save_alt, color: colorScheme.primary),
              tooltip: 'Save edits',
              onPressed: _saveWithEdits,
            ),
          IconButton(
            icon: Icon(_isEditing ? Icons.visibility : Icons.edit),
            tooltip: _isEditing ? 'Preview' : 'Edit',
            onPressed: () => setState(() => _isEditing = !_isEditing),
          ),
          IconButton(
            icon: const Icon(Icons.timer_outlined),
            tooltip: 'Set timer',
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => const AddTimerModal(),
              );
            },
          ),
          if (settings.aiEnabled)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'format' && recipe.fullContent.isNotEmpty) {
                  ref.invalidate(availableModelsProvider);
                  context.push('/transcode', extra: recipe.fullContent);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'format',
                  child: ListTile(
                    leading: Icon(Icons.auto_fix_high),
                    title: Text('Format with AI'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Reader'),
            Tab(text: 'Editor'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          MarkdownReader(
            recipe: recipe,
            rootPath: rootPath,
            imagePathFor: imageResolver,
          ),
          MarkdownEditor(
            initialContent: recipe.fullContent,
            onChanged: (v) =>
                ref.read(recipeContentProvider.notifier).state = v,
          ),
        ],
      ),
    );
  }

  String _factorLabel(double f) {
    if (f == 0.5) return '½';
    if (f == f.roundToDouble()) return '${f.toInt()}×';
    return '${f.toStringAsFixed(1)}×';
  }
}
