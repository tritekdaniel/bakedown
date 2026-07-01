import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/recipe_model.dart';

abstract class RecipeRepository {
  String? get rootPath;

  Future<List<String>> listFolders();
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
    try {
      final dir = Directory(rootPath);
      if (!dir.existsSync()) return [];
      return dir.listSync()
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
      if (!dir.existsSync()) return [];
      return dir.listSync()
          .where((e) => e.path.endsWith('.md'))
          .map((e) {
            final content = File(e.path).readAsStringSync();
            return RecipeModel.fromMarkdown(
              content,
              fileName: p.basename(e.path),
              folder: folder,
            );
          })
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<String?> readFile(String folder, String filename) async {
    try {
      final file = File(p.join(rootPath, folder, filename));
      if (!file.existsSync()) return null;
      return file.readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> writeFile(
      String folder, String filename, String content) async {
    try {
      final file = File(p.join(rootPath, folder, filename));
      file.createSync(recursive: true);
      file.writeAsStringSync(content);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> deleteFile(String folder, String filename) async {
    try {
      final file = File(p.join(rootPath, folder, filename));
      if (file.existsSync()) file.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> deleteFolder(String folderName) async {
    try {
      final dir = Directory(p.join(rootPath, folderName));
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> createFolder(String folderName) async {
    try {
      Directory(p.join(rootPath, folderName)).createSync(recursive: true);
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
