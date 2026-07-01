import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_app/features/recipes/data/repositories/recipe_repository.dart';

void main() {
  group('LocalRecipeRepository', () {
    late Directory tempDir;
    late LocalRecipeRepository repo;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('recipe_repo_test_');
      repo = LocalRecipeRepository(tempDir.path);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('listFolders returns empty for new directory', () async {
      final folders = await repo.listFolders();
      expect(folders, isEmpty);
    });

    test('createFolder creates directory and listFolders returns it', () async {
      final ok = await repo.createFolder('desserts');
      expect(ok, true);
      final folders = await repo.listFolders();
      expect(folders, ['desserts']);
    });

    test('createFolder is idempotent for existing folder', () async {
      await repo.createFolder('soups');
      final ok = await repo.createFolder('soups');
      expect(ok, true);
    });

    test('deleteFolder removes directory', () async {
      await repo.createFolder('test-folder');
      final ok = await repo.deleteFolder('test-folder');
      expect(ok, true);
      final folders = await repo.listFolders();
      expect(folders, isEmpty);
    });

    test('writeFile creates .md file and readFile reads it back', () async {
      await repo.createFolder('entrees');
      final content = '---\ntitle: Test Recipe\n---\n\nBody';
      final ok = await repo.writeFile('entrees', 'test.md', content);
      expect(ok, true);
      final read = await repo.readFile('entrees', 'test.md');
      expect(read, content);
    });

    test('writeFile creates subdirectory if needed', () async {
      final content = '# Auto-created';
      final ok = await repo.writeFile('new-folder', 'recipe.md', content);
      expect(ok, true);
      final folders = await repo.listFolders();
      expect(folders, contains('new-folder'));
    });

    test('readFile returns null for missing file', () async {
      final result = await repo.readFile('nonexistent', 'missing.md');
      expect(result, isNull);
    });

    test('deleteFile removes .md file', () async {
      await repo.createFolder('veg');
      await repo.writeFile('veg', 'side.md', '# Side dish');
      final ok = await repo.deleteFile('veg', 'side.md');
      expect(ok, true);
      final read = await repo.readFile('veg', 'side.md');
      expect(read, isNull);
    });

    test('listRecipes returns parsed RecipeModel', () async {
      await repo.createFolder('breakfast');
      await repo.writeFile('breakfast', 'pancakes.md',
          '---\ntitle: Pancakes\nservings: 4\n---\n\n## Ingredients\n- Flour');
      final recipes = await repo.listRecipes('breakfast');
      expect(recipes.length, 1);
      expect(recipes.first.title, 'Pancakes');
      expect(recipes.first.servings, 4);
    });

    test('listRecipes ignores non-.md files', () async {
      await repo.createFolder('mixed');
      await repo.writeFile('mixed', 'recipe.md', '---\ntitle: Real\n---\n');
      final noteFile = File('${tempDir.path}/mixed/note.txt');
      noteFile.writeAsStringSync('not a recipe');
      final recipes = await repo.listRecipes('mixed');
      expect(recipes.length, 1);
    });

    test('listRecipes returns empty for nonexistent folder', () async {
      final recipes = await repo.listRecipes('ghost');
      expect(recipes, isEmpty);
    });

    test('imagePathFor returns joined path', () async {
      final path = await repo.imagePathFor('folder', 'img.jpg');
      expect(path, contains('folder${Platform.pathSeparator}img.jpg'));
    });

    test('rootPath matches constructor argument', () async {
      expect(repo.rootPath, tempDir.path);
    });
  });
}
