import 'package:recipe_app/shared/utils/android_saf_helper.dart';
import '../models/recipe_model.dart';
import 'recipe_repository.dart';

class AndroidSafRecipeRepository implements RecipeRepository {
  final String treeUri;

  @override
  String get rootPath => treeUri;

  AndroidSafRecipeRepository(this.treeUri);

  @override
  Future<List<String>> listFolders() async {
    return listSubfolders('');
  }

  @override
  Future<List<String>> listSubfolders(String folder) async {
    final files = await AndroidSafHelper.listFiles(treeUri, subDir: folder.isEmpty ? null : folder);
    return files
        .where((f) => f.isDirectory)
        .map((f) => f.name)
        .toList()
      ..sort();
  }

  @override
  Future<List<RecipeModel>> listRecipes(String folder) async {
    final files = await AndroidSafHelper.listFiles(treeUri, subDir: folder);
    final mdFiles = files.where((f) => !f.isDirectory && f.name.endsWith('.md'));
    final results = <RecipeModel>[];
    for (final f in mdFiles) {
      final content = await AndroidSafHelper.readFile(treeUri, folder, f.name);
      if (content != null) {
        results.add(RecipeModel.fromMarkdown(
          content,
          fileName: f.name,
          folder: folder,
        ));
      }
    }
    return results;
  }

  @override
  Future<String?> readFile(String folder, String filename) async {
    return AndroidSafHelper.readFile(treeUri, folder, filename);
  }

  @override
  Future<bool> writeFile(String folder, String filename, String content) async {
    return AndroidSafHelper.writeFile(treeUri, folder, filename, content);
  }

  @override
  Future<bool> deleteFile(String folder, String filename) async {
    return AndroidSafHelper.deleteFile(treeUri, folder, filename);
  }

  @override
  Future<bool> deleteFolder(String folderName) async {
    return AndroidSafHelper.deleteDirectory(treeUri, folderName);
  }

  @override
  Future<bool> createFolder(String folderName) async {
    return AndroidSafHelper.createDirectory(treeUri, folderName);
  }

  @override
  Future<String> imagePathFor(String folder, String fileName) async {
    return '$treeUri/$folder/$fileName';
  }
}
