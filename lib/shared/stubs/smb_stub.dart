import 'dart:async';

class SmbConnect {
  static Future<SmbConnect> connectAuth({required String host, String domain = '', required String username, required String password, bool forceSmb1 = false, bool debugPrint = false}) async => SmbConnect();
  Future<SmbFile> file(String path) async => SmbFile();
  Future<List<SmbFile>> listFiles(SmbFile f) async => [];
  Future<List<SmbShare>> listShares() async => [];
  Future<Stream<List<int>>> openRead(SmbFile f) async => const Stream.empty();
  Future<SmbWriter> openWrite(SmbFile f) async => SmbWriter();
  Future<SmbFile> createFile(String path) async => SmbFile();
  Future<void> createFolder(String path) async {}
  Future<void> delete(SmbFile f) async {}
  Future<void> close() async {}
}
class SmbFile {
  String get path => '';
  bool isDirectory() => false;
  bool get isExists => false;
}
class SmbShare { String get path => ''; }
class SmbWriter {
  void add(List<int> d) {}
  Future<void> flush() async {}
  Future<void> close() async {}
}
