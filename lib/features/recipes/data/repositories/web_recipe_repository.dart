import 'package:shared_preferences/shared_preferences.dart';
import '../models/recipe_model.dart';
import 'recipe_repository.dart';

class WebRecipeRepository implements RecipeRepository {
  @override
  String get rootPath => 'web';

  static const _foldersKey = 'web_recipe_folders';
  static const _prefix = 'web_recipe_content_';

  String _key(String folder, String filename) => '$_prefix${folder}__$filename';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<List<String>> listFolders() async {
    final p = await _prefs;
    final folders = p.getStringList(_foldersKey) ?? [];
    final keys = p.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final k in keys) {
      final rest = k.substring(_prefix.length);
      final idx = rest.indexOf('__');
      if (idx > 0) {
        final folder = rest.substring(0, idx);
        if (!folders.contains(folder)) folders.add(folder);
      }
    }
    return folders;
  }

  @override
  Future<List<String>> listSubfolders(String folder) async {
    final all = await listFolders();
    if (folder.isEmpty) {
      return all.where((f) => !f.contains('/')).toList()..sort();
    }
    final prefix = '$folder/';
    final sub = <String>{};
    for (final f in all) {
      if (f.startsWith(prefix)) {
        final rest = f.substring(prefix.length);
        final seg = rest.split('/').first;
        if (seg.isNotEmpty) sub.add(seg);
      }
    }
    // also check if any file key implies subfolder exists without explicit folder entry
    final p = await _prefs;
    final keys = p.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final k in keys) {
      final rest = k.substring(_prefix.length);
      final idx = rest.indexOf('__');
      if (idx <= 0) continue;
      final fullFolder = rest.substring(0, idx);
      if (fullFolder.startsWith(prefix)) {
        final after = fullFolder.substring(prefix.length);
        final seg = after.split('/').first;
        if (seg.isNotEmpty) sub.add(seg);
      }
    }
    final list = sub.toList()..sort();
    return list;
  }

  @override
  Future<List<RecipeModel>> listRecipes(String folder) async {
    final p = await _prefs;
    final keys = p.getKeys().where((k) => k.startsWith(_prefix + folder + '__')).toList();
    final result = <RecipeModel>[];
    for (final k in keys) {
      final content = p.getString(k);
      if (content == null) continue;
      final filename = k.substring((_prefix + folder + '__').length);
      result.add(RecipeModel.fromMarkdown(content, fileName: filename, folder: folder));
    }
    result.sort((a, b) => a.title.compareTo(b.title));
    return result;
  }

  @override
  Future<String?> readFile(String folder, String filename) async {
    final p = await _prefs;
    return p.getString(_key(folder, filename));
  }

  @override
  Future<bool> writeFile(String folder, String filename, String content) async {
    final p = await _prefs;
    await p.setString(_key(folder, filename), content);
    final folders = p.getStringList(_foldersKey) ?? [];
    if (!folders.contains(folder)) {
      folders.add(folder);
      await p.setStringList(_foldersKey, folders);
    }
    return true;
  }

  @override
  Future<bool> deleteFile(String folder, String filename) async {
    final p = await _prefs;
    await p.remove(_key(folder, filename));
    final remaining = p.getKeys().where((k) => k.startsWith(_prefix + folder + '__')).length;
    if (remaining == 0) {
      final folders = p.getStringList(_foldersKey) ?? [];
      final hasSubfolders = folders.any((f) => f.startsWith('$folder/'));
      final hasNestedFiles = p.getKeys().any((k) {
        if (!k.startsWith(_prefix)) return false;
        final rest = k.substring(_prefix.length);
        final idx = rest.indexOf('__');
        if (idx <= 0) return false;
        final f = rest.substring(0, idx);
        return f.startsWith('$folder/');
      });
      if (!hasSubfolders && !hasNestedFiles) {
        folders.remove(folder);
        await p.setStringList(_foldersKey, folders);
      }
    }
    return true;
  }

  @override
  Future<bool> deleteFolder(String folderName) async {
    final p = await _prefs;
    final keys = p.getKeys().toList();
    final toDeleteKeys = keys.where((k) {
      if (!k.startsWith(_prefix)) return false;
      final rest = k.substring(_prefix.length);
      final idx = rest.indexOf('__');
      if (idx <= 0) return false;
      final folder = rest.substring(0, idx);
      return folder == folderName || folder.startsWith('$folderName/');
    }).toList();
    for (final k in toDeleteKeys) {
      await p.remove(k);
    }
    final folders = p.getStringList(_foldersKey) ?? [];
    // Remove folder and any nested child folders
    folders.removeWhere((f) => f == folderName || f.startsWith('$folderName/'));
    await p.setStringList(_foldersKey, folders);
    return true;
  }

  @override
  Future<bool> createFolder(String folderName) async {
    final p = await _prefs;
    final folders = p.getStringList(_foldersKey) ?? [];
    if (!folders.contains(folderName)) {
      folders.add(folderName);
      await p.setStringList(_foldersKey, folders);
    }
    return true;
  }

  @override
  Future<String> imagePathFor(String folder, String fileName) async => '';
}
