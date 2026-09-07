import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';
// ignore: avoid_web_libraries_in_flutter
import 'package:web/web.dart' as web;
import 'package:recipe_app/features/recipes/data/repositories/web_recipe_repository.dart';

class WebLegacyPicker {
  static Future<int> pickAndImportFolder() async {
    if (!kIsWeb) return 0;
    try {
      final input = web.document.createElement('input') as web.HTMLInputElement
        ..type = 'file'
        ..multiple = true;
      // webkitdirectory is non-standard but works in Chrome/Edge
      input.setAttribute('webkitdirectory', '');
      input.setAttribute('directory', '');
      input.accept = '.md';

      final completer = Completer<List<web.File>>();
      input.onChange.listen((_) {
        final files = input.files;
        if (files == null) {
          completer.complete([]);
        } else {
          final list = <web.File>[];
          for (var i = 0; i < files.length; i++) {
            final f = files.item(i);
            if (f != null) list.add(f);
          }
          completer.complete(list);
        }
      });

      // Must be triggered in user gesture - click the input
      input.click();
      final files = await completer.future.timeout(const Duration(minutes: 5), onTimeout: () => <web.File>[]);
      if (files.isEmpty) return 0;

      final repo = WebRecipeRepository();
      int imported = 0;
      for (final file in files) {
        try {
          final name = file.name;
          if (!name.toLowerCase().endsWith('.md')) continue;
          final relPath = (file as JSObject).getProperty('webkitRelativePath'.toJS) as JSString?;
          final relative = relPath?.toDart ?? name;
          final parts = relative.split('/');
          // parts[0] is picked folder name, rest is subpath
          String folder;
          if (parts.length == 1) {
            folder = 'imported';
          } else if (parts.length == 2) {
            folder = parts[0];
          } else {
            final sub = parts.sublist(1, parts.length - 1).join('/');
            folder = sub.isEmpty ? parts[0] : sub;
            // Handle nested like a/b/c/file.md -> sub is b/c
            if (folder.isEmpty) folder = 'imported';
          }
          final filename = name;
          final content = await file.text().toDart as String;
          if (content.isNotEmpty) {
            await repo.writeFile(folder, filename, content);
            imported++;
          }
        } catch (e) {
          debugPrint('[WEB_LEGACY] import $file failed: $e');
        }
      }
      // Clean up
      input.remove();
      return imported;
    } catch (e) {
      debugPrint('[WEB_LEGACY] pickAndImportFolder failed: $e');
      return 0;
    }
  }
}
