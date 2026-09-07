import 'dart:io' if (dart.library.html) 'package:recipe_app/shared/stubs/io_stub.dart';
import 'package:path/path.dart' as p;
import '../models/recipe_model.dart';

abstract class RecipeRepository {
  String? get rootPath;

  Future<List<String>> listFolders();
  Future<List<String>> listSubfolders(String folder);
  Future<List<RecipeModel>> listRecipes(String folder);
  Future<String?> readFile(String folder, String filename);
  Future<bool> writeFile(String folder, String filename, String content);
  Future<bool> deleteFile(String folder, String filename);
  Future<bool> deleteFolder(String folderName);
  Future<bool> createFolder(String folderName);
  Future<String> imagePathFor(String folder, String fileName);
}

class LocalRecipeRepository implements RecipeRepository {
  @override
  final String rootPath;

  LocalRecipeRepository(this.rootPath);

  @override
  Future<List<String>> listFolders() async {
    return listSubfolders('');
  }

  Future<T> _withTimeout<T>(Future<T> f, Duration d, T fallback) async {
    try {
      return await f.timeout(d);
    } catch (_) {
      return fallback;
    }
  }

  @override
  Future<List<String>> listSubfolders(String folder) async {
    try {
      final target = folder.isEmpty ? rootPath : p.join(rootPath, folder);
      final dir = Directory(target);
      final entries = await _withTimeout(dir.list().toList(), const Duration(seconds: 3), <FileSystemEntity>[]);
      return entries
          .whereType<Directory>()
          .map((e) => p.basename(e.path))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<RecipeModel>> listRecipes(String folder) async {
    try {
      final dir = Directory(p.join(rootPath, folder));
      final entries = await _withTimeout(dir.list().toList(), const Duration(seconds: 3), <FileSystemEntity>[]);
      if (entries.isEmpty) return [];
      final mdFiles = entries.where((e) => e.path.toLowerCase().endsWith('.md')).toList();
      if (mdFiles.isEmpty) return [];
      final futures = mdFiles.map((e) async {
        try {
          final file = File(e.path);
          final content = await _withTimeout(file.readAsString(), const Duration(seconds: 2), '');
          if (content.isEmpty) return null;
          return RecipeModel.fromMarkdown(
            content,
            fileName: p.basename(e.path),
            folder: folder,
          );
        } catch (_) {
          return null;
        }
      });
      final results = await Future.wait(futures);
      return results.whereType<RecipeModel>().toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<String?> readFile(String folder, String filename) async {
    try {
      final file = File(p.join(rootPath, folder, filename));
      final exists = await _withTimeout(file.exists(), const Duration(seconds: 2), false);
      if (!exists) return null;
      return await _withTimeout(file.readAsString(), const Duration(seconds: 2), null);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> writeFile(
      String folder, String filename, String content) async {
    try {
      final file = File(p.join(rootPath, folder, filename));
      await _withTimeout(file.create(recursive: true), const Duration(seconds: 2), file);
      await _withTimeout(file.writeAsString(content), const Duration(seconds: 2), file);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> deleteFile(String folder, String filename) async {
    try {
      final file = File(p.join(rootPath, folder, filename));
      final exists = await _withTimeout(file.exists(), const Duration(seconds: 1), false);
      if (exists) await _withTimeout(file.delete(), const Duration(seconds: 2), file);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> deleteFolder(String folderName) async {
    try {
      final dir = Directory(p.join(rootPath, folderName));
      final exists = await _withTimeout(dir.exists(), const Duration(seconds: 1), false);
      if (exists) await _withTimeout(dir.delete(recursive: true), const Duration(seconds: 3), null);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> createFolder(String folderName) async {
    try {
      final dir = Directory(p.join(rootPath, folderName));
      await _withTimeout(dir.create(recursive: true), const Duration(seconds: 2), dir);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String> imagePathFor(String folder, String fileName) async {
    return p.join(rootPath, folder, fileName);
  }
}
