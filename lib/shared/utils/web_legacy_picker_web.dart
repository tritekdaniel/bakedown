import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:recipe_app/features/recipes/data/repositories/web_recipe_repository.dart';

class WebLegacyPicker {
  static Future<int> pickAndImportFolder() async {
    if (!kIsWeb) return 0;
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        withReadStream: false,
        type: FileType.custom,
        allowedExtensions: ['md'],
      );
      if (result == null || result.files.isEmpty) return 0;

      final repo = WebRecipeRepository();
      int imported = 0;
      for (final f in result.files) {
        try {
          final name = f.name;
          if (!name.toLowerCase().endsWith('.md')) continue;
          final bytes = f.bytes;
          if (bytes == null || bytes.isEmpty) continue;
          String content;
          try {
            content = utf8.decode(bytes);
          } catch (_) {
            content = String.fromCharCodes(bytes);
          }
          if (content.isEmpty) continue;
          const folder = 'imported';
          await repo.writeFile(folder, name, content);
          imported++;
        } catch (e) {
          debugPrint('[WEB_LEGACY] import ${f.name} failed: $e');
        }
      }
      return imported;
    } catch (e) {
      debugPrint('[WEB_LEGACY] pickAndImportFolder failed: $e');
      return 0;
    }
  }
}
