import 'dart:typed_data';

bool get isFileSystemAccessSupported => false;
bool get isSecureContext => true;
String get currentOrigin => '';
String get localhostAlternative => 'http://localhost:2211/';

class WebFsHelper {
  static bool get hasHandle => false;
  static String? get rootName => null;
  static dynamic get handle => null;
  static void setHandle(dynamic handle, String name) {}
  static Future<dynamic> pickDirectory() async => null;
  static Future<bool> ensurePermission() async => false;
  static Future<List<String>> listEntries(String folder, {required bool directoriesOnly, String? extensionFilter}) async => [];
  static Future<String?> readFile(String folder, String filename) async => null;
  static Future<bool> writeFile(String folder, String filename, String content) async => false;
  static Future<bool> deleteFile(String folder, String filename) async => false;
  static Future<bool> deleteFolder(String folderName) async => false;
  static Future<bool> createFolder(String folderName) async => false;
  static Future<Uint8List?> readFileBytes(String folder, String filename) async => null;
  static Future<String> createImageUrl(String folder, String fileName) async => '';
}
