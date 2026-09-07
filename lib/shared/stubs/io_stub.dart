abstract class FileSystemEntity {
  String get path;
}

class File implements FileSystemEntity {
  @override
  final String path;
  File(this.path);
  bool existsSync() => false;
  String readAsStringSync() => '';
  void createSync({bool recursive = false}) {}
  void writeAsStringSync(String content) {}
  void deleteSync() {}
  Future<bool> exists() async => false;
  Future<File> create({bool recursive = false}) async => this;
  Future<void> writeAsBytes(List<int> bytes) async {}
  Future<List<int>> readAsBytes() async => [];
  Future<String> readAsString() async => '';
  Future<File> writeAsString(String content) async => this;
  Future<File> copy(String newPath) async => File(newPath);
  File get absolute => this;
  Future<void> delete({bool recursive = false}) async {}
  Future<File> createTemp(String prefix) async => File('');
  dynamic openWrite() => _StubSink();
}

class Directory implements FileSystemEntity {
  @override
  final String path;
  Directory(this.path);
  bool existsSync() => false;
  List<FileSystemEntity> listSync() => [];
  Stream<FileSystemEntity> list({bool recursive = false, bool followLinks = true}) => const Stream.empty();
  void createSync({bool recursive = false}) {}
  void deleteSync({bool recursive = false}) {}
  Future<bool> exists() async => false;
  Future<Directory> create({bool recursive = false}) async => this;
  Future<Directory> createTemp(String prefix) async => Directory('');
  Future<void> delete({bool recursive = false}) async {}
  static Directory get systemTemp => Directory('');
}

class _StubSink {
  void add(List<int> data) {}
  Future<void> flush() async {}
  Future<void> close() async {}
  void write(String s) {}
}

class ProcessResult {
  final int exitCode = 1;
  final dynamic stdout = '';
  final dynamic stderr = '';
}

class Process {
  static Future<ProcessResult> run(String executable, List<String> args) async => ProcessResult();
  static Future<ProcessResult> runSync(String executable, List<String> args) => Future.value(ProcessResult());
}

class InternetAddress {
  final String address;
  InternetAddress(this.address);
  static InternetAddress loopbackIPv4 = InternetAddress('127.0.0.1');
}

// ignore: constant_identifier_names
enum InternetAddressType { IPv4, IPv6, any }

class NetworkInterface {
  final String name;
  final List<InternetAddress> addresses;
  NetworkInterface(this.name, this.addresses);
  static Future<List<NetworkInterface>> list({bool includeLoopback = false, bool includeLinkLocal = false, InternetAddressType type = InternetAddressType.any}) async => [];
}

class Socket {
  static Future<Socket> connect(dynamic host, int port, {Duration? timeout, dynamic sourceAddress}) async => Socket();
  void destroy() {}
  void close() {}
}
