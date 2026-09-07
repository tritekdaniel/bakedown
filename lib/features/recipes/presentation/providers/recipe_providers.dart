import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/recipe_repository.dart';
import '../../data/repositories/android_saf_recipe_repository.dart';
import '../../data/repositories/http_recipe_repository.dart';
import '../../data/models/recipe_model.dart';
import 'package:recipe_app/features/settings/presentation/providers/settings_providers.dart';
import 'package:recipe_app/shared/utils/android_saf_helper.dart';

final smbConnectRequestProvider = StateProvider<int>((ref) => 0);

final webFsHandleRevisionProvider = StateProvider<int>((ref) => 0);
final webUseBrowserStorageProvider = StateProvider<bool>((ref) => false);

final recipeRepositoryProvider = FutureProvider<RecipeRepository?>((ref) async {
  ref.watch(smbConnectRequestProvider);
  ref.watch(webFsHandleRevisionProvider);
  ref.watch(webUseBrowserStorageProvider);
  final httpBridgeEnabled = ref.watch(settingsProvider.select((s) => s.httpBridgeEnabled));
  final httpBridgeUrl = ref.watch(settingsProvider.select((s) => s.httpBridgeUrl));
  final recipeDirectory = ref.watch(settingsProvider.select((s) => s.recipeDirectory));

  if (kIsWeb) {
    final origin = Uri.base.origin;
    if (origin.isNotEmpty && origin != 'null') {
      return HttpRecipeRepository(origin);
    }
    return HttpRecipeRepository('http://localhost:2211');
  }

  if (httpBridgeEnabled && httpBridgeUrl.isNotEmpty) {
    return HttpRecipeRepository(httpBridgeUrl);
  }

  if (recipeDirectory.isEmpty) return null;
  final dir = recipeDirectory;
  if (defaultTargetPlatform == TargetPlatform.android && dir.startsWith('content://')) {
    try {
      await AndroidSafHelper.takePersistablePermission(dir);
      return AndroidSafRecipeRepository(dir);
    } catch (_) {
      return null;
    }
  }
  return LocalRecipeRepository(dir);
});

final foldersProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(refreshCounterProvider);
  final repo = await ref.watch(recipeRepositoryProvider.future);
  if (repo == null) return [];
  return repo.listFolders();
});

final subfoldersProvider = FutureProvider.family<List<String>, String>((ref, folder) async {
  ref.watch(refreshCounterProvider);
  final repo = await ref.watch(recipeRepositoryProvider.future);
  if (repo == null) return [];
  return repo.listSubfolders(folder);
});

final currentFolderProvider = StateProvider<String>((ref) => '');

final refreshCounterProvider = StateProvider<int>((ref) => 0);

final recipesInFolderProvider = FutureProvider<List<RecipeModel>>((ref) async {
  ref.watch(refreshCounterProvider);
  final repo = await ref.watch(recipeRepositoryProvider.future);
  final folder = ref.watch(currentFolderProvider);
  if (repo == null || folder.isEmpty) return [];
  return repo.listRecipes(folder);
});

final currentRecipeProvider = StateProvider<RecipeModel?>((ref) => null);

final recipeContentProvider = StateProvider<String>((ref) => '');

final recipeSearchQueryProvider = StateProvider<String>((ref) => '');

final debouncedSearchQueryProvider = StateProvider<String>((ref) => '');

final allRecipesProvider = FutureProvider<List<RecipeModel>>((ref) async {
  try {
    final repo = await ref.watch(recipeRepositoryProvider.future);
    if (repo == null) return [];
    ref.watch(refreshCounterProvider);
    Future<List<String>> collectAllFolders(String parent) async {
      try {
        final subs = await repo.listSubfolders(parent);
        if (subs.isEmpty) return [];
        final deeperLists = await Future.wait(subs.map((s) async {
          final full = parent.isEmpty ? s : '$parent/$s';
          try {
            final deeper = await collectAllFolders(full);
            return [full, ...deeper];
          } catch (e) {
            debugPrint('[ALL_RECIPES] collect $full failed: $e');
            return [full];
          }
        }));
        return deeperLists.expand((l) => l).toList();
      } catch (e) {
        debugPrint('[ALL_RECIPES] listSubfolders $parent failed: $e');
        return [];
      }
    }

    final allFolders = await collectAllFolders('');
    if (allFolders.isEmpty) return [];
    final results = await Future.wait(
      allFolders.map((f) async {
        try {
          return await repo.listRecipes(f);
        } catch (e) {
          debugPrint('[ALL_RECIPES] listRecipes $f failed: $e');
          return <RecipeModel>[];
        }
      }),
    );
    return results.expand((r) => r).toList();
  } catch (e, st) {
    debugPrint('[ALL_RECIPES] fatal $e $st');
    return [];
  }
});

final filteredRecipesProvider = Provider<AsyncValue<List<RecipeModel>>>((ref) {
  final query = ref.watch(debouncedSearchQueryProvider).trim().toLowerCase();
  if (query.isEmpty) return const AsyncValue.data([]);
  final allAsync = ref.watch(allRecipesProvider);
  return allAsync.whenData((recipes) => recipes.where((r) {
    final title = r.title.toLowerCase();
    final tags = r.tags.map((t) => t.toLowerCase());
    return title.contains(query) || tags.any((t) => t.contains(query));
  }).toList());
});

final scaleFactorProvider = StateProvider<double>((ref) => 1.0);

class MemoryEditsNotifier extends StateNotifier<Map<String, String>> {
  MemoryEditsNotifier() : super({});

  void setEdit(String original, String edited) {
    final updated = Map<String, String>.from(state);
    updated[original] = edited;
    state = updated;
  }

  void removeEdit(String original) {
    final copy = Map<String, String>.from(state);
    copy.remove(original);
    state = copy;
  }

  void clearAll() {
    state = {};
  }

  bool get hasEdits => state.isNotEmpty;
}

final memoryEditsProvider =
    StateNotifierProvider<MemoryEditsNotifier, Map<String, String>>(
  (ref) => MemoryEditsNotifier(),
);

class UnitConversionNotifier extends StateNotifier<Map<String, String>> {
  UnitConversionNotifier() : super({});

  void setConversion(String original, String converted) {
    final updated = Map<String, String>.from(state);
    updated[original] = converted;
    state = updated;
  }

  void removeConversion(String original) {
    final copy = Map<String, String>.from(state);
    copy.remove(original);
    state = copy;
  }

  void clearAll() {
    state = {};
  }
}

final unitConversionProvider =
    StateNotifierProvider<UnitConversionNotifier, Map<String, String>>(
  (ref) => UnitConversionNotifier(),
);

final recipeSectionsProvider = Provider<Map<String, List<String>>>((ref) {
  final content = ref.watch(recipeContentProvider);
  if (content.isEmpty) return {};
  return _parseRecipeSections(content);
});

final _headingSplitRe = RegExp(r'^##\s+(.+)$', multiLine: true);

Map<String, List<String>> _parseRecipeSections(String markdown) {
  final result = <String, List<String>>{};
  String? currentSection;
  final ingredients = <String>[];
  final instructions = <String>[];
  final other = <String>[];
  final headingRe = _headingSplitRe;

  final lines = markdown.split('\n');
  for (final line in lines) {
    final match = headingRe.firstMatch(line);
    if (match != null) {
      currentSection = match.group(1)!.toLowerCase().trim();
      continue;
    }
    if (currentSection == null) continue;
    if (line.trim().isEmpty) continue;

    if (currentSection.contains('ingredient')) {
      ingredients.add(line);
    } else if (currentSection.contains('instruction') ||
        currentSection.contains('direction') ||
        currentSection.contains('steps') ||
        currentSection.contains('method')) {
      instructions.add(line);
    } else {
      other.add(line);
    }
  }

  if (ingredients.isNotEmpty) result['ingredients'] = ingredients;
  if (instructions.isNotEmpty) result['instructions'] = instructions;
  if (other.isNotEmpty) result['other'] = other;

  return result;
}

Future<String?> smbImagePath(
    RecipeRepository? repo, String folder, String fileName) async {
  if (repo == null) return null;
  try {
    return await repo.imagePathFor(folder, fileName);
  } catch (_) {
    return null;
  }
}
