import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
// ignore: avoid_web_libraries_in_flutter
import 'package:web/web.dart' as web;

bool get isSecureContext {
  if (!kIsWeb) return true;
  try {
    final v = (web.window as JSObject).getProperty('isSecureContext'.toJS) as JSBoolean?;
    return v?.toDart ?? true;
  } catch (_) {
    return true;
  }
}

String get currentOrigin {
  if (!kIsWeb) return '';
  try {
    return web.window.location.origin;
  } catch (_) {
    return '';
  }
}

String get localhostAlternative {
  if (!kIsWeb) return '';
  try {
    final loc = web.window.location;
    final port = loc.port.isEmpty ? '' : ':${loc.port}';
    return '${loc.protocol}//localhost$port/';
  } catch (_) {
    return 'http://localhost:2211/';
  }
}

bool get isFileSystemAccessSupported {
  if (!kIsWeb) return false;
  try {
    if (!isSecureContext) return false;
    final prop = (web.window as JSObject).getProperty('showDirectoryPicker'.toJS);
    return prop != null;
  } catch (_) {
    return false;
  }
}

class WebFsHelper {
  static JSAny? _rootHandle;
  static String? _rootName;

  static bool get hasHandle => _rootHandle != null;
  static String? get rootName => _rootName;
  static JSAny? get handle => _rootHandle;

  static void setHandle(JSAny handle, String name) {
    _rootHandle = handle;
    _rootName = name;
  }

  static Future<JSAny?> pickDirectory() async {
    try {
      final win = web.window as JSObject;
      // Call without options for maximum compatibility — defaults to readwrite
      // Must be called directly in user gesture, no await before it
      final promise = win.callMethod<JSPromise<JSAny?>>('showDirectoryPicker'.toJS);
      final handle = await promise.toDart as JSAny?;
      if (handle == null) return null;
      try {
        final perm = await (handle as JSObject).callMethod<JSPromise<JSString>>('requestPermission'.toJS, jsify({'mode': 'readwrite'}) as JSAny).toDart as String;
        if (perm != 'granted') {
          final q = await (handle as JSObject).callMethod<JSPromise<JSString>>('queryPermission'.toJS, jsify({'mode': 'readwrite'}) as JSAny).toDart as String;
          if (q != 'granted') return null;
        }
      } catch (_) {}
      final name = (handle as JSObject).getProperty<JSString>('name'.toJS)?.toDart ?? 'web-folder';
      setHandle(handle, name);
      return handle;
    } catch (e) {
      debugPrint('[WEB_FS] pickDirectory failed: $e');
      return null;
    }
  }

  static Future<bool> ensurePermission() async {
    final h = _rootHandle;
    if (h == null) return false;
    try {
      final state = await (h as JSObject).callMethod<JSPromise<JSString>>('queryPermission'.toJS, jsify({'mode': 'readwrite'}) as JSAny).toDart as String;
      if (state == 'granted') return true;
      final req = await (h as JSObject).callMethod<JSPromise<JSString>>('requestPermission'.toJS, jsify({'mode': 'readwrite'}) as JSAny).toDart as String;
      return req == 'granted';
    } catch (_) {
      return true;
    }
  }

  static Future<JSAny?> _getDirectory(List<String> segments, {bool create = false}) async {
    var current = _rootHandle;
    if (current == null) return null;
    if (!await ensurePermission()) return null;
    for (final seg in segments) {
      if (seg.isEmpty) continue;
      try {
        current = await (current! as JSObject).callMethod<JSPromise<JSAny?>>('getDirectoryHandle'.toJS, seg.toJS, jsify({'create': create}) as JSAny).toDart as JSAny?;
        if (current == null) return null;
      } catch (_) {
        return null;
      }
    }
    return current;
  }

  static Future<List<String>> listEntries(String folder, {required bool directoriesOnly, String? extensionFilter}) async {
    final dir = folder.isEmpty
        ? _rootHandle
        : await _getDirectory(folder.split('/').where((s) => s.isNotEmpty).toList());
    if (dir == null) return [];
    try {
      return await _collectHandles(dir, directoriesOnly, extensionFilter);
    } catch (e) {
      debugPrint('[WEB_FS] listEntries $folder failed: $e');
      return [];
    }
  }

  static Future<List<String>> _collectHandles(JSAny dir, bool dirOnly, String? ext) async {
    try {
      final out = <String>[];
      final iterator = (dir as JSObject).callMethod<JSAny>('values'.toJS) as JSAny;
      while (true) {
        final nextResult = await (iterator as JSObject).callMethod<JSPromise<JSAny?>>('next'.toJS).toDart as JSAny?;
        if (nextResult == null) break;
        final done = (nextResult as JSObject).getProperty<JSBoolean>('done'.toJS)?.toDart ?? false;
        if (done) break;
        final handle = (nextResult as JSObject).getProperty<JSAny>('value'.toJS);
        if (handle == null) continue;
        final kind = (handle as JSObject).getProperty<JSString>('kind'.toJS)?.toDart ?? '';
        final name = (handle as JSObject).getProperty<JSString>('name'.toJS)?.toDart ?? '';
        if (dirOnly) {
          if (kind == 'directory') out.add(name);
        } else {
          if (kind == 'file') {
            if (ext == null || name.toLowerCase().endsWith(ext.toLowerCase())) out.add(name);
          }
        }
      }
      return out;
    } catch (e) {
      debugPrint('[WEB_FS] _collectHandles failed: $e');
      return [];
    }
  }

  static Future<String?> readFile(String folder, String filename) async {
    try {
      final dir = folder.isEmpty
          ? _rootHandle
          : await _getDirectory(folder.split('/').where((s) => s.isNotEmpty).toList());
      if (dir == null) return null;
      final fileHandle = await (dir as JSObject).callMethod<JSPromise<JSAny?>>('getFileHandle'.toJS, filename.toJS).toDart as JSAny?;
      if (fileHandle == null) return null;
      final file = await (fileHandle as JSObject).callMethod<JSPromise<JSAny?>>('getFile'.toJS).toDart as JSAny?;
      if (file == null) return null;
      final text = await (file as JSObject).callMethod<JSPromise<JSString>>('text'.toJS).toDart as String;
      return text;
    } catch (e) {
      debugPrint('[WEB_FS] readFile $folder/$filename failed: $e');
      return null;
    }
  }

  static Future<bool> writeFile(String folder, String filename, String content) async {
    try {
      final dir = folder.isEmpty
          ? _rootHandle
          : await _getDirectory(folder.split('/').where((s) => s.isNotEmpty).toList(), create: true);
      if (dir == null) return false;
      final fileHandle = await (dir as JSObject).callMethod<JSPromise<JSAny?>>('getFileHandle'.toJS, filename.toJS, jsify({'create': true}) as JSAny).toDart as JSAny?;
      if (fileHandle == null) return false;
      final writable = await (fileHandle as JSObject).callMethod<JSPromise<JSAny?>>('createWritable'.toJS).toDart as JSAny?;
      if (writable == null) return false;
      await (writable as JSObject).callMethod<JSPromise<JSAny?>>('write'.toJS, content.toJS).toDart;
      await (writable as JSObject).callMethod<JSPromise<JSAny?>>('close'.toJS).toDart;
      return true;
    } catch (e) {
      debugPrint('[WEB_FS] writeFile $folder/$filename failed: $e');
      return false;
    }
  }

  static Future<bool> deleteFile(String folder, String filename) async {
    try {
      final dir = folder.isEmpty
          ? _rootHandle
          : await _getDirectory(folder.split('/').where((s) => s.isNotEmpty).toList());
      if (dir == null) return false;
      await (dir as JSObject).callMethod<JSPromise<JSAny?>>('removeEntry'.toJS, filename.toJS).toDart;
      return true;
    } catch (e) {
      debugPrint('[WEB_FS] deleteFile $folder/$filename failed: $e');
      return false;
    }
  }

  static Future<bool> deleteFolder(String folderName) async {
    try {
      final parts = folderName.split('/').where((s) => s.isNotEmpty).toList();
      if (parts.isEmpty) return false;
      final name = parts.last;
      final parentParts = parts.sublist(0, parts.length - 1);
      final parentDir = parentParts.isEmpty ? _rootHandle : await _getDirectory(parentParts);
      if (parentDir == null) return false;
      await (parentDir as JSObject).callMethod<JSPromise<JSAny?>>('removeEntry'.toJS, name.toJS, jsify({'recursive': true}) as JSAny).toDart;
      return true;
    } catch (e) {
      debugPrint('[WEB_FS] deleteFolder $folderName failed: $e');
      return false;
    }
  }

  static Future<bool> createFolder(String folderName) async {
    try {
      final parts = folderName.split('/').where((s) => s.isNotEmpty).toList();
      final dir = await _getDirectory(parts, create: true);
      return dir != null;
    } catch (e) {
      debugPrint('[WEB_FS] createFolder $folderName failed: $e');
      return false;
    }
  }

  static Future<Uint8List?> readFileBytes(String folder, String filename) async {
    try {
      final dir = folder.isEmpty
          ? _rootHandle
          : await _getDirectory(folder.split('/').where((s) => s.isNotEmpty).toList());
      if (dir == null) return null;
      final fileHandle = await (dir as JSObject).callMethod<JSPromise<JSAny?>>('getFileHandle'.toJS, filename.toJS).toDart as JSAny?;
      if (fileHandle == null) return null;
      final file = await (fileHandle as JSObject).callMethod<JSPromise<JSAny?>>('getFile'.toJS).toDart as JSAny?;
      if (file == null) return null;
      final buffer = await (file as JSObject).callMethod<JSPromise<JSArrayBuffer>>('arrayBuffer'.toJS).toDart as JSArrayBuffer;
      return buffer.toDart.asUint8List();
    } catch (e) {
      debugPrint('[WEB_FS] readFileBytes $folder/$filename failed: $e');
      return null;
    }
  }

  static Future<String> createImageUrl(String folder, String fileName) async {
    try {
      final bytes = await readFileBytes(folder, fileName);
      if (bytes == null) return '';
      final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: _mimeFor(fileName)));
      final url = web.URL.createObjectURL(blob);
      return url;
    } catch (_) {
      return '';
    }
  }

  static String _mimeFor(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (ext == 'png') return 'image/png';
    if (ext == 'webp') return 'image/webp';
    if (ext == 'gif') return 'image/gif';
    return 'image/jpeg';
  }

  static JSAny? jsify(Object? obj) {
    if (obj == null) return null;
    if (obj is Map) {
      final jsObj = JSObject();
      obj.forEach((k, v) {
        jsObj.setProperty(k.toString().toJS, (v as Object?).jsify());
      });
      return jsObj as JSAny;
    }
    if (obj is String) return obj.toJS;
    if (obj is bool) return obj.toJS;
    if (obj is num) return obj.toJS;
    return obj.toString().toJS;
  }
}

extension _Jsify on Object? {
  JSAny? jsify() {
    if (this == null) return null;
    if (this is String) return (this as String).toJS;
    if (this is bool) return (this as bool).toJS;
    if (this is int) return (this as int).toJS;
    if (this is double) return (this as double).toJS;
    if (this is Map) {
      final o = JSObject();
      (this as Map).forEach((k, v) {
        o.setProperty(k.toString().toJS, v.jsify());
      });
      return o as JSAny;
    }
    return this.toString().toJS;
  }
}
