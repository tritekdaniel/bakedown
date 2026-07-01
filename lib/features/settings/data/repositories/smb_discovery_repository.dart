import 'package:nsd/nsd.dart';
import '../../domain/models/discovered_server.dart';

class SmbDiscoveryRepository {
  Discovery? _discovery;

  Future<List<DiscoveredServer>> startScan({
    required void Function(DiscoveredServer server, bool added) onChanged,
  }) async {
    await stopScan();
    _discovery = await startDiscovery(
      '_microsoft-ds._tcp',
      ipLookupType: IpLookupType.any,
    );
    _discovery!.addServiceListener((service, status) {
      final server = DiscoveredServer(
        name: service.name ?? 'Unknown',
        host: service.host ?? service.name ?? 'Unknown',
        port: service.port ?? 445,
      );
      onChanged(server, status == ServiceStatus.found);
    });
    return _discovery!.services
        .map((s) => DiscoveredServer(
              name: s.name ?? 'Unknown',
              host: s.host ?? s.name ?? 'Unknown',
              port: s.port ?? 445,
            ))
        .toList();
  }

  bool get isScanning => _discovery != null;

  Future<void> stopScan() async {
    if (_discovery != null) {
      await stopDiscovery(_discovery!);
      _discovery = null;
    }
  }

  void dispose() {
    stopScan();
  }
}
