import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SafFileInfo {
  final String name;
  final bool isDirectory;
  final String? mimeType;

  SafFileInfo({required this.name, required this.isDirectory, this.mimeType});

  factory SafFileInfo.fromMap(Map<String, dynamic> map) {
    return SafFileInfo(
      name: map['name'] as String,
      isDirectory: map['isDirectory'] as bool,
      mimeType: map['mimeType'] as String?,
    );
  }
}

class AndroidSafHelper {
  static const _channel = MethodChannel('recipe_app/saf');

  static bool get isAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> takePersistablePermission(String treeUri) async {
    if (!isAvailable) return true;
    try {
      return await _channel.invokeMethod('takePersistablePermission', {
        'treeUri': treeUri,
      });
    } catch (_) {
      return false;
    }
  }

  static Future<List<SafFileInfo>> listFiles(String treeUri, {String? subDir}) async {
    if (!isAvailable) return [];
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('listFiles', {
        'treeUri': treeUri,
        'subDir': subDir,
      });
      return (result ?? [])
          .map((e) => SafFileInfo.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<String?> readFile(String treeUri, String subDir, String fileName) async {
    if (!isAvailable) return null;
    try {
      final bytes = await _channel.invokeMethod<List<int>>('readFile', {
        'treeUri': treeUri,
        'subDir': subDir,
        'fileName': fileName,
      });
      if (bytes == null) return null;
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> writeFile(
      String treeUri, String subDir, String fileName, String content) async {
    if (!isAvailable) return false;
    try {
      return await _channel.invokeMethod<bool>('writeFile', {
        'treeUri': treeUri,
        'subDir': subDir,
        'fileName': fileName,
        'content': utf8.encode(content),
      }) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> createDirectory(String treeUri, String name) async {
    if (!isAvailable) return false;
    try {
      return await _channel.invokeMethod<bool>('createDirectory', {
        'treeUri': treeUri,
        'name': name,
      }) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteFile(String treeUri, String subDir, String fileName) async {
    if (!isAvailable) return false;
    try {
      return await _channel.invokeMethod<bool>('deleteFile', {
        'treeUri': treeUri,
        'subDir': subDir,
        'fileName': fileName,
      }) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteDirectory(String treeUri, String name) async {
    if (!isAvailable) return false;
    try {
      return await _channel.invokeMethod<bool>('deleteDirectory', {
        'treeUri': treeUri,
        'name': name,
      }) ?? false;
    } catch (_) {
      return false;
    }
  }
}
