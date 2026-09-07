import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:recipe_app/shared/utils/web_fs_helper.dart';
import '../models/recipe_model.dart';
import 'recipe_repository.dart';

class WebFsRecipeRepository implements RecipeRepository {
  @override
  String? get rootPath => WebFsHelper.rootName ?? 'web-fs';

  @override
  Future<List<String>> listFolders() async {
    if (!WebFsHelper.hasHandle) return [];
    final all = await WebFsHelper.listEntries('', directoriesOnly: true);
    // also include nested folders discovered via files? listEntries already covers top level
    // Need to also return nested folder paths that exist as directories with files
    // For web FS, listEntries gives top level only, but we need all folders recursively discovered
    // For now return top level; listSubfolders handles nesting
    return all;
  }

  @override
  Future<List<String>> listSubfolders(String folder) async {
    if (!WebFsHelper.hasHandle) return [];
    return WebFsHelper.listEntries(folder, directoriesOnly: true);
  }

  @override
  Future<List<RecipeModel>> listRecipes(String folder) async {
    if (!WebFsHelper.hasHandle) return [];
    final files = await WebFsHelper.listEntries(folder, directoriesOnly: false, extensionFilter: '.md');
    final result = <RecipeModel>[];
    for (final f in files) {
      final content = await WebFsHelper.readFile(folder, f);
      if (content == null) continue;
      result.add(RecipeModel.fromMarkdown(content, fileName: f, folder: folder));
    }
    result.sort((a, b) => a.title.compareTo(b.title));
    return result;
  }

  @override
  Future<String?> readFile(String folder, String filename) async {
    if (!WebFsHelper.hasHandle) return null;
    return WebFsHelper.readFile(folder, filename);
  }

  @override
  Future<bool> writeFile(String folder, String filename, String content) async {
    if (!WebFsHelper.hasHandle) return false;
    return WebFsHelper.writeFile(folder, filename, content);
  }

  @override
  Future<bool> deleteFile(String folder, String filename) async {
    if (!WebFsHelper.hasHandle) return false;
    return WebFsHelper.deleteFile(folder, filename);
  }

  @override
  Future<bool> deleteFolder(String folderName) async {
    if (!WebFsHelper.hasHandle) return false;
    return WebFsHelper.deleteFolder(folderName);
  }

  @override
  Future<bool> createFolder(String folderName) async {
    if (!WebFsHelper.hasHandle) return false;
    return WebFsHelper.createFolder(folderName);
  }

  @override
  Future<String> imagePathFor(String folder, String fileName) async {
    if (!WebFsHelper.hasHandle) return '';
    final bytes = await WebFsHelper.readFileBytes(folder, fileName);
    if (bytes == null) return '';
    if (kIsWeb) {
      // Create blob URL for web display
      return WebFsHelper.createImageUrl(folder, fileName);
    }
    return '';
  }
}
