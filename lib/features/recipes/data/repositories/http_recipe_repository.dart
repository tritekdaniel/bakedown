import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/recipe_model.dart';
import 'recipe_repository.dart';

class HttpRecipeRepository implements RecipeRepository {
  final String baseUrl;
  final Dio _dio;

  HttpRecipeRepository(String url)
      : baseUrl = url.replaceAll(RegExp(r'/+$'), ''),
        _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 10),
          headers: {'Accept': 'application/json'},
          validateStatus: (_) => true,
        )) {
    _dio.options.baseUrl = baseUrl;
  }

  @override
  String? get rootPath => baseUrl;

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  @override
  Future<List<String>> listFolders() async {
    try {
      final resp = await _dio.get('/api/folders');
      if (resp.statusCode == 200) {
        final data = resp.data;
        if (data is List) return data.map((e) => e.toString()).toList();
        if (data is Map && data['folders'] is List) {
          return (data['folders'] as List).map((e) => e.toString()).toList();
        }
      }
      final alt = await _dio.get('/api/list');
      if (alt.statusCode == 200 && alt.data is Map && (alt.data as Map)['folders'] is List) {
        return ((alt.data as Map)['folders'] as List).map((e) => e.toString()).toList();
      }
    } catch (e) {
      debugPrint('[HTTP_REPO] listFolders failed: $e');
    }
    return [];
  }

  @override
  Future<List<String>> listSubfolders(String folder) async {
    if (folder.isEmpty) return listFolders();
    try {
      final encodedFolder = Uri.encodeComponent(folder);
      final resp = await _dio.get('/api/folders/$encodedFolder/subfolders');
      if (resp.statusCode == 200) {
        final data = resp.data;
        if (data is List) return data.map((e) => e.toString()).toList();
        if (data is Map && data['folders'] is List) {
          return (data['folders'] as List).map((e) => e.toString()).toList();
        }
      }
      final resp2 = await _dio.get('/api/folders/$encodedFolder');
      if (resp2.statusCode == 200) {
        final data = resp2.data;
        if (data is Map && data['folders'] is List) {
          return (data['folders'] as List).map((e) => e.toString()).toList();
        }
        if (data is List) {
          // Old bridge returns just files, can't know subfolders
          return [];
        }
      }
    } catch (e) {
      debugPrint('[HTTP_REPO] listSubfolders $folder failed: $e');
    }
    try {
      final all = await listFolders();
      final prefix = '$folder/';
      final sub = <String>{};
      for (final f in all) {
        if (f.startsWith(prefix)) {
          final seg = f.substring(prefix.length).split('/').first;
          if (seg.isNotEmpty) sub.add(seg);
        }
      }
      return sub.toList()..sort();
    } catch (_) {}
    return [];
  }

  @override
  Future<List<RecipeModel>> listRecipes(String folder) async {
    try {
      final resp = await _dio.get(
        '/api/folders/${Uri.encodeComponent(folder)}',
      );
      if (resp.statusCode == 200) {
        final data = resp.data;
        List<String> files = [];
        if (data is List) {
          files = data.map((e) => e.toString()).toList();
        } else if (data is Map && data['files'] is List) {
          files = (data['files'] as List).map((e) => e.toString()).toList();
        } else if (data is Map && data['recipes'] is List) {
          // bridge returned full recipe objects
          final recipesRaw = data['recipes'] as List;
          return recipesRaw.map((r) {
            final m = r as Map<String, dynamic>;
            final content = m['content'] as String? ?? '';
            final fname = m['filename'] as String? ?? m['fileName'] as String? ?? 'unknown.md';
            return RecipeModel.fromMarkdown(content, fileName: fname, folder: folder);
          }).toList();
        }

        // Files are .md names, fetch each
        final mdFiles = files.where((f) => f.endsWith('.md')).toList();
        final recipes = <RecipeModel>[];
        for (final f in mdFiles) {
          final content = await readFile(folder, f);
          if (content != null) {
            recipes.add(RecipeModel.fromMarkdown(content, fileName: f, folder: folder));
          }
        }
        return recipes;
      }
    } catch (e) {
      debugPrint('[HTTP_REPO] listRecipes $folder failed: $e');
    }
    return [];
  }

  @override
  Future<String?> readFile(String folder, String filename) async {
    try {
      final resp = await _dio.get(
        '/api/file/${Uri.encodeComponent(folder)}/${Uri.encodeComponent(filename)}',
        options: Options(responseType: ResponseType.plain),
      );
      if (resp.statusCode == 200) {
        if (resp.data is String) return resp.data as String;
        if (resp.data is Map && resp.data['content'] is String) {
          return resp.data['content'] as String;
        }
        return resp.data.toString();
      }
      final alt = await _dio.get(
        '/files/${Uri.encodeComponent(folder)}/${Uri.encodeComponent(filename)}',
        options: Options(responseType: ResponseType.plain),
      );
      if (alt.statusCode == 200 && alt.data is String) return alt.data as String;
    } catch (e) {
      debugPrint('[HTTP_REPO] readFile $folder/$filename failed: $e');
    }
    return null;
  }

  @override
  Future<bool> writeFile(String folder, String filename, String content) async {
    try {
      final resp = await _dio.put(
        '/api/file/${Uri.encodeComponent(folder)}/${Uri.encodeComponent(filename)}',
        data: content,
        options: Options(contentType: 'text/markdown', headers: {'Content-Type': 'text/markdown'}),
      );
      if (resp.statusCode == 200 || resp.statusCode == 201) return true;

      final resp2 = await _dio.post(
        '/api/file',
        data: {'folder': folder, 'filename': filename, 'content': content},
        options: Options(contentType: 'application/json'),
      );
      return resp2.statusCode == 200 || resp2.statusCode == 201;
    } catch (e) {
      debugPrint('[HTTP_REPO] writeFile failed: $e');
      return false;
    }
  }

  @override
  Future<bool> deleteFile(String folder, String filename) async {
    try {
      final resp = await _dio.delete('/api/file/${Uri.encodeComponent(folder)}/${Uri.encodeComponent(filename)}');
      return resp.statusCode == 200 || resp.statusCode == 204;
    } catch (e) {
      debugPrint('[HTTP_REPO] deleteFile failed: $e');
      return false;
    }
  }

  @override
  Future<bool> deleteFolder(String folderName) async {
    try {
      final resp = await _dio.delete('/api/folder/${Uri.encodeComponent(folderName)}');
      return resp.statusCode == 200 || resp.statusCode == 204;
    } catch (e) {
      debugPrint('[HTTP_REPO] deleteFolder failed: $e');
      return false;
    }
  }

  @override
  Future<bool> createFolder(String folderName) async {
    try {
      final resp = await _dio.post('/api/folder/${Uri.encodeComponent(folderName)}');
      if (resp.statusCode == 200 || resp.statusCode == 201) return true;
      final resp2 = await _dio.post('/api/folders', data: {'name': folderName}, options: Options(contentType: 'application/json'));
      return resp2.statusCode == 200 || resp2.statusCode == 201;
    } catch (e) {
      debugPrint('[HTTP_REPO] createFolder failed: $e');
      return false;
    }
  }

  Future<bool> writeBytes(String folder, String filename, Uint8List bytes, {String contentType = 'application/octet-stream'}) async {
    try {
      final resp = await _dio.put(
        '/files/${Uri.encodeComponent(folder)}/${Uri.encodeComponent(filename)}',
        data: bytes,
        options: Options(contentType: contentType, headers: {'Content-Type': contentType}),
      );
      return resp.statusCode == 200 || resp.statusCode == 201;
    } catch (e) {
      debugPrint('[HTTP_REPO] writeBytes $folder/$filename failed: $e');
      return false;
    }
  }

  @override
  Future<String> imagePathFor(String folder, String fileName) async {
    // Return direct HTTP URL for <img> on web, or cached path fallback
    // For web, gpt_markdown / markdown_reader can load via network
    // For native, we could download to temp but return HTTP URL is simplest
    return '$baseUrl/files/${Uri.encodeComponent(folder)}/${Uri.encodeComponent(fileName)}';
  }

  Future<Uint8List?> fetchImageBytes(String folder, String fileName) async {
    try {
      final resp = await _dio.get('/files/${Uri.encodeComponent(folder)}/${Uri.encodeComponent(fileName)}', options: Options(responseType: ResponseType.bytes));
      if (resp.statusCode == 200 && resp.data is List<int>) {
        return Uint8List.fromList(resp.data as List<int>);
      }
      if (resp.data is Uint8List) return resp.data as Uint8List;
    } catch (e) {
      debugPrint('[HTTP_REPO] fetchImage failed: $e');
    }
    return null;
  }

  Future<bool> testConnection() async {
    try {
      final resp = await _dio.get('/api/folders');
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
