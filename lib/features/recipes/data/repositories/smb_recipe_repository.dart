import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:smb_connect/smb_connect.dart';
import '../models/recipe_model.dart';
import 'recipe_repository.dart';

class SmbRecipeRepository implements RecipeRepository {
  final String host;
  final String domain;
  final String username;
  final String password;
  final String share;
  final String subPath;

  SmbConnect? _connect;
  String? _shareName;
  String _shareSubPath = '';
  Directory? _tempDir;

  SmbRecipeRepository({
    required this.host,
    this.domain = '',
    required this.username,
    required this.password,
    required this.share,
    this.subPath = '',
  });

  Future<void> connect({bool debugPrint = kDebugMode}) async {
    final effectiveDomain = domain.isEmpty ? 'WORKGROUP' : domain;
    final cleanShare = share.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
    final parts = cleanShare.split('/');
    final shareName = parts.first;
    _shareSubPath = parts.length > 1 ? parts.sublist(1).join('/') : '';

    Object? firstErr;
    for (final retry in [false, true]) {
      try {
        _connect = await SmbConnect.connectAuth(
          host: host,
          domain: effectiveDomain,
          username: username,
          password: password,
          forceSmb1: retry,
          debugPrint: debugPrint,
        );
        _shareName = '/$shareName';
        _tempDir = await Directory.systemTemp.createTemp('recipe_app_smb_');
        return;
      } catch (e) {
        if (retry) {
          final combined = firstErr ?? e;
          final errStr = combined.toString().toLowerCase();
          final isAuth = errStr.contains('auth') ||
              errStr.contains('logon') ||
              errStr.contains('credential') ||
              errStr.contains('access denied') ||
              errStr.contains('status_logon_failure');
          final msg = isAuth
              ? 'Auth failed — check: username (not email), password, '
                  'domain ($effectiveDomain), try `server min protocol = NT1` '
                  'in smb.conf'
              : 'SMB connection failed: $combined';
          print('SmbRecipeRepository.connect error: $msg');
          throw Exception(msg);
        }
        firstErr = e;
      }
    }
  }

  SmbConnect get _c {
    if (_connect == null) throw StateError('SmbRecipeRepository not connected');
    return _connect!;
  }

  String get _basePath {
    var path = _shareSubPath.isNotEmpty
        ? '$_shareName/$_shareSubPath'
        : _shareName!;
    if (subPath.isNotEmpty) {
      path = '$path/${subPath.replaceAll(RegExp(r'^/+|/+$'), '')}';
    }
    return path;
  }

  String _joinSmbPath(String folder, String filename) {
    return '$_basePath/$folder/$filename';
  }

  String _folderPath(String folder) {
    return '$_basePath/$folder';
  }

  @override
  String? get rootPath => null;

  @override
  Future<List<String>> listFolders() async {
    try {
      final rootDir = await _c.file(_basePath);
      final files = await _c.listFiles(rootDir);
      return files
          .where((f) => f.isDirectory())
          .map((f) => p.basename(f.path))
          .where((n) => n.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<String> diagnostics() async {
    try {
      final rootDir = await _c.file(_basePath);
      final files = await _c.listFiles(rootDir);
      final dirs = files.where((f) => f.isDirectory()).toList();
      final nonDirs = files.where((f) => !f.isDirectory()).toList();
      final sub = _shareSubPath.isNotEmpty ? '/$_shareSubPath' : '';
      final pathInfo = subPath.isNotEmpty ? '$sub/$subPath' : sub;
      return 'Share: $share$pathInfo — ${dirs.length} folder(s), ${nonDirs.length} file(s)';
    } catch (e) {
      return 'Error listing share: $e';
    }
  }

  Future<List<String>> listShares() async {
    try {
      final shares = await _c.listShares();
      return shares.map((s) => s.path).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<RecipeModel>> listRecipes(String folder) async {
    try {
      final folderFile = await _c.file(_folderPath(folder));
      final files = await _c.listFiles(folderFile);
      final mdFiles = files.where((f) => f.path.endsWith('.md')).toList();
      final recipes = <RecipeModel>[];

      for (final f in mdFiles) {
        try {
          final content = await _readSmbFile(f);
          final fileName = p.basename(f.path);
          recipes.add(RecipeModel.fromMarkdown(
            content,
            fileName: fileName,
            folder: folder,
          ));
        } catch (_) {
        }
      }

      return recipes;
    } catch (_) {
      return [];
    }
  }

  Future<String> _readSmbFile(SmbFile file) async {
    final reader = await _c.openRead(file);
    return await reader.asyncMap((event) => utf8.decode(event)).join('');
  }

  @override
  Future<String?> readFile(String folder, String filename) async {
    try {
      final file = await _c.file(_joinSmbPath(folder, filename));
      return await _readSmbFile(file);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> writeFile(
      String folder, String filename, String content) async {
    try {
      final path = _joinSmbPath(folder, filename);
      SmbFile file;
      try {
        file = await _c.file(path);
      } catch (_) {
        file = await _c.createFile(path);
      }
      final writer = await _c.openWrite(file);
      writer.add(utf8.encode(content));
      await writer.flush();
      await writer.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> deleteFile(String folder, String filename) async {
    try {
      final file = await _c.file(_joinSmbPath(folder, filename));
      await _c.delete(file);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> deleteFolder(String folderName) async {
    try {
      final dir = await _c.file(_folderPath(folderName));
      await _c.delete(dir);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> createFolder(String folderName) async {
    try {
      final path = _folderPath(folderName);
      try {
        final existing = await _c.file(path);
        if (existing.isExists) return true;
      } catch (_) {
      }
      await _c.createFolder(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String> imagePathFor(String folder, String fileName) async {
    try {
      final cacheDir = _tempDir;
      if (cacheDir == null) return '';

      final cacheFile = File(p.join(cacheDir.path, fileName));
      if (await cacheFile.exists()) return cacheFile.path;

      final smbFile = await _c.file(_joinSmbPath(folder, fileName));
      final reader = await _c.openRead(smbFile);
      await cacheFile.create(recursive: true);
      final sink = cacheFile.openWrite();
      await reader.forEach((chunk) => sink.add(chunk));
      await sink.flush();
      await sink.close();

      return cacheFile.path;
    } catch (_) {
      return '';
    }
  }

  Future<void> dispose() async {
    if (_connect != null) {
      await _connect!.close();
      _connect = null;
    }
    if (_tempDir != null && await _tempDir!.exists()) {
      await _tempDir!.delete(recursive: true);
    }
  }
}
