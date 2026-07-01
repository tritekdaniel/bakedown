import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_app/features/recipes/data/models/recipe_model.dart';

void main() {
  group('RecipeModel.fromMarkdown', () {
    test('parses servings with (estimated) suffix', () {
      final content = '''---
title: Eggnog
servings: 4 (estimated)
difficulty: easy
tags: [eggnog, holiday]
source: ""
---
## Ingredients
- [ ] 2 eggs
''';
      final recipe = RecipeModel.fromMarkdown(content, fileName: 'test.md');
      expect(recipe.title, 'Eggnog');
      expect(recipe.servings, 4);
      expect(recipe.difficulty, 'easy');
      expect(recipe.tags, ['eggnog', 'holiday']);
    });

    test('parses servings as pure int', () {
      final content = '''---
title: Naan
servings: 8
difficulty: medium
tags: [naan, bread]
source: ""
---
## Ingredients
- [ ] 2 cups flour
''';
      final recipe = RecipeModel.fromMarkdown(content, fileName: 'test.md');
      expect(recipe.servings, 8);
    });

    test('parses servings with mixed text', () {
      final content = '''---
title: Test
servings: about 6 servings
---
''';
      final recipe = RecipeModel.fromMarkdown(content, fileName: 'test.md');
      expect(recipe.servings, 6);
    });

    test('handles missing servings', () {
      final content = '''---
title: Test
difficulty: easy
---
''';
      final recipe = RecipeModel.fromMarkdown(content, fileName: 'test.md');
      expect(recipe.servings, isNull);
    });

    test('handles empty frontmatter gracefully', () {
      final content = 'Just some text without frontmatter';
      final recipe = RecipeModel.fromMarkdown(content, fileName: 'test.md');
      expect(recipe.title, 'Test');
      expect(recipe.servings, isNull);
      expect(recipe.tags, isEmpty);
    });

    test('handles numeric prep_time (int instead of string)', () {
      final content = '''---
title: Test
prep_time: 15
servings: 4
---
''';
      final recipe = RecipeModel.fromMarkdown(content, fileName: 'test.md');
      expect(recipe.title, 'Test');
      expect(recipe.prepTime, '15');
      expect(recipe.servings, 4);
    });
  });
}
