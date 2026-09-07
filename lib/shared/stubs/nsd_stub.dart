import 'dart:async';

class Service {
  final String? name;
  final String? host;
  final int? port;
  Service({this.name, this.host, this.port});
}

enum ServiceStatus { found, lost }

enum IpLookupType { none, v4, v6, any }

class Discovery {
  final String id;
  Discovery(this.id);
  List<Service> get services => [];
  void addServiceListener(dynamic Function(Service, ServiceStatus) l) {}
}

Future<Discovery> startDiscovery(String serviceType, {bool autoResolve = true, IpLookupType ipLookupType = IpLookupType.none}) async => Discovery('stub');
Future<void> stopDiscovery(Discovery discovery) async {}
