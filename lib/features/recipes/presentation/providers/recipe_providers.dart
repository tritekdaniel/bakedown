import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/recipe_repository.dart';
import '../../data/repositories/android_saf_recipe_repository.dart';
import '../../data/repositories/smb_recipe_repository.dart';
import '../../data/models/recipe_model.dart';
import 'package:recipe_app/features/settings/presentation/providers/settings_providers.dart';
import 'package:recipe_app/shared/utils/android_saf_helper.dart';

final smbConnectRequestProvider = StateProvider<int>((ref) => 0);

final _smbAutoConnectedProvider = StateProvider<bool>((ref) => false);

final recipeRepositoryProvider = FutureProvider<RecipeRepository?>((ref) async {
  ref.watch(smbConnectRequestProvider);
  ref.watch(settingsProvider);
  final settings = ref.read(settingsProvider);

  if (!settings.smbEnabled) {
    if (settings.recipeDirectory.isEmpty) return null;
    final dir = settings.recipeDirectory;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android &&
        dir.startsWith('content://')) {
      try {
        await AndroidSafHelper.takePersistablePermission(dir);
        return AndroidSafRecipeRepository(dir);
      } catch (_) {
        return null;
      }
    }
    return LocalRecipeRepository(dir);
  }

  if (settings.smbHost.isEmpty || settings.smbShare.isEmpty) return null;

  final trigger = ref.read(smbConnectRequestProvider);
  if (trigger == 0) {
    final autoConnected = ref.read(_smbAutoConnectedProvider);
    if (!autoConnected &&
        settings.smbHost.isNotEmpty &&
        settings.smbShare.isNotEmpty) {
      Future.microtask(() {
        ref.read(_smbAutoConnectedProvider.notifier).state = true;
        ref.read(smbConnectRequestProvider.notifier).state++;
      });
    }
    return null;
  }

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    final uncPath = '\\\\${settings.smbHost}\\${settings.smbShare}';
    final userPart = settings.smbDomain.isNotEmpty
        ? '${settings.smbDomain}\\${settings.smbUser}'
        : settings.smbUser;
    try {
      final result = await Process.run('net', [
        'use', uncPath,
        '/user:$userPart',
        settings.smbPassword,
      ]);
      if (result.exitCode != 0) {
        final stderr = (result.stderr as String?)?.trim() ?? '';
        throw Exception('net use failed ($stderr)');
      }
    } catch (_) {
      final repo = SmbRecipeRepository(
        host: settings.smbHost,
        domain: settings.smbDomain,
        username: settings.smbUser,
        password: settings.smbPassword,
        share: settings.smbShare,
        subPath: settings.smbPath,
      );
      try {
        await repo.connect(debugPrint: kDebugMode);
        return repo;
      } catch (_) {
        return null;
      }
    }
    return LocalRecipeRepository(uncPath);
  }

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final repo = SmbRecipeRepository(
        host: settings.smbHost,
        domain: settings.smbDomain,
        username: settings.smbUser,
        password: settings.smbPassword,
        share: settings.smbShare,
        subPath: settings.smbPath,
      );
      await repo.connect(debugPrint: kDebugMode);
      ref.onDispose(() async {
        try {
          await repo.dispose();
        } catch (_) {}
      });
      return repo;
    } catch (_) {
      return null;
    }
  }

  return null;
});

final foldersProvider = FutureProvider<List<String>>((ref) async {
  final repo = ref.watch(recipeRepositoryProvider).valueOrNull;
  if (repo == null) return [];
  return repo.listFolders();
});

final currentFolderProvider = StateProvider<String>((ref) => '');

final refreshCounterProvider = StateProvider<int>((ref) => 0);

final recipesInFolderProvider = FutureProvider<List<RecipeModel>>((ref) async {
  ref.watch(refreshCounterProvider);
  final repo = ref.watch(recipeRepositoryProvider).valueOrNull;
  final folder = ref.watch(currentFolderProvider);
  if (repo == null || folder.isEmpty) return [];
  return repo.listRecipes(folder);
});

final currentRecipeProvider = StateProvider<RecipeModel?>((ref) => null);

final recipeContentProvider = StateProvider<String>((ref) => '');

final recipeSearchQueryProvider = StateProvider<String>((ref) => '');

final allRecipesProvider = FutureProvider<List<RecipeModel>>((ref) async {
  final repo = ref.watch(recipeRepositoryProvider).valueOrNull;
  if (repo == null) return [];
  final folders = await repo.listFolders();
  final results = await Future.wait(
    folders.map((f) => repo.listRecipes(f)),
  );
  return results.expand((r) => r).toList();
});

final filteredRecipesProvider = Provider<AsyncValue<List<RecipeModel>>>((ref) {
  final allAsync = ref.watch(allRecipesProvider);
  final query = ref.watch(recipeSearchQueryProvider).trim().toLowerCase();
  if (query.isEmpty) return allAsync;
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

Map<String, List<String>> _parseRecipeSections(String markdown) {
  final result = <String, List<String>>{};
  String? currentSection;
  final ingredients = <String>[];
  final instructions = <String>[];
  final other = <String>[];
  final headingRe = RegExp(r'^##\s+(.+)$', multiLine: true);

  final lines = markdown.split('\n');
  for (final line in lines) {
    final match = headingRe.firstMatch(line);
    if (match != null) {
      currentSection = match.group(1)!.toLowerCase().trim();
      continue;
    }
    if (currentSection == null) continue;
    if (line.trim().isEmpty) continue;

    if (currentSection!.contains('ingredient')) {
      ingredients.add(line);
    } else if (currentSection!.contains('instruction') ||
        currentSection!.contains('direction') ||
        currentSection!.contains('steps') ||
        currentSection!.contains('method')) {
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
