import '../../domain/models/discovered_server.dart';

// Stub — OS file picker now handles network shares. Kept for compat.
class SmbDiscoveryRepository {
  Future<List<DiscoveredServer>> startScan({
    required void Function(DiscoveredServer server, bool added) onChanged,
  }) async =>
      [];

  Future<List<String>> listSharesAuthenticated(
    String host, {
    String domain = '',
    String username = '',
    String password = '',
  }) async =>
      [];

  Future<void> stopScan() async {}

  void dispose() {}
}
