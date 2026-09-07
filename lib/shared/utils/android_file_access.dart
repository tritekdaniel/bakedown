import 'dart:io' if (dart.library.html) 'package:recipe_app/shared/stubs/io_stub.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

enum StorageAccess { granted, denied, restricted }

Future<StorageAccess> requestStorageAccess() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return StorageAccess.granted;
  }

  if (await Permission.manageExternalStorage.isGranted) {
    return StorageAccess.granted;
  }

  if (await Permission.storage.isGranted) {
    return StorageAccess.granted;
  }

  var status = await Permission.manageExternalStorage.request();
  // request() polling can miss the grant — do a fresh check
  if (status.isGranted || await Permission.manageExternalStorage.isGranted) {
    return StorageAccess.granted;
  }

  if (status.isPermanentlyDenied) {
    return StorageAccess.restricted;
  }

  // Fresh check again in case the delayed broadcast arrived
  if (await Permission.manageExternalStorage.isGranted) {
    return StorageAccess.granted;
  }

  status = await Permission.storage.request();
  if (status.isGranted) return StorageAccess.granted;

  return StorageAccess.denied;
}

Future<bool> hasStorageAccess() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return true;
  }
  return await Permission.manageExternalStorage.isGranted ||
      await Permission.storage.isGranted;
}

String? resolveContentUri(String path) {
  if (path.startsWith('/')) return path;
  if (!path.startsWith('content://')) return path;

  final uri = Uri.tryParse(path);
  if (uri == null) return null;

  final segments = uri.pathSegments;
  final treeIdx = segments.indexOf('tree');
  if (treeIdx < 0 || segments.length <= treeIdx + 1) return null;

  // Use only the segment immediately after tree/ (ignore document/ etc.)
  final encoded = segments[treeIdx + 1];
  final decoded = Uri.decodeQueryComponent(encoded);
  final colonIdx = decoded.indexOf(':');

  String storageId;
  String relativePath;
  if (colonIdx >= 0) {
    storageId = decoded.substring(0, colonIdx);
    relativePath = decoded.substring(colonIdx + 1);
  } else {
    storageId = decoded;
    relativePath = '';
  }

  if (storageId == 'primary') {
    if (relativePath.isEmpty) return '/storage/emulated/0';
    return '/storage/emulated/0/$relativePath';
  }

  if (relativePath.isEmpty) return '/storage/$storageId';
  return '/storage/$storageId/$relativePath';
}

Future<String?> resolveRecipeDirectory(String rawPath) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return rawPath.isEmpty ? null : rawPath;
  }

  if (rawPath.startsWith('content://')) {
    final resolved = resolveContentUri(rawPath);
    if (resolved != null) {
      final dir = Directory(resolved);
      if (await dir.exists()) return resolved;
      try {
        await dir.create(recursive: true);
        return resolved;
      } catch (_) {}
    }
    return rawPath;
  }

  final dir = Directory(rawPath);
  if (await dir.exists()) return rawPath;

  try {
    await dir.create(recursive: true);
    return rawPath;
  } catch (_) {
    return null;
  }
}

Future<bool> showPermissionDeniedDialog(BuildContext context) async {
  final permissionStatus = await Permission.manageExternalStorage.status;
  if (!context.mounted) return false;

  final isPermanentlyDenied = permissionStatus.isPermanentlyDenied;

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Storage Access Required'),
      content: Text(
        isPermanentlyDenied
            ? 'Enable "Files and media" access in Settings > Apps > Bakedown > Permissions.'
            : 'This app needs storage access to read and write recipe files.\n\n'
                'If you already enabled it, tap "Check again".',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            if (isPermanentlyDenied) {
              await openAppSettings();
            }
            // Re-check after returning from settings
            final granted = await Permission.manageExternalStorage.isGranted;
            if (ctx.mounted) Navigator.pop(ctx, granted);
          },
          child: const Text('Check again'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.pop(ctx, false);
            await openAppSettings();
          },
          child: const Text('Open Settings'),
        ),
      ],
    ),
  );

  return result ?? false;
}
