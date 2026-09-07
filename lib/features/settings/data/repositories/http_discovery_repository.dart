import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../domain/models/discovered_server.dart';

class HttpDiscoveryRepository {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 3),
    receiveTimeout: const Duration(seconds: 5),
    validateStatus: (_) => true,
  ));

  Future<List<DiscoveredServer>> discoverViaBridge(String bridgeUrl) async {
    if (bridgeUrl.isEmpty) return [];
    final base = bridgeUrl.replaceAll(RegExp(r'/+$'), '');
    try {
      final resp = await _dio.get('$base/api/discover');
      if (resp.statusCode == 200) {
        final data = resp.data;
        if (data is List) {
          return data.map((e) => _fromJson(e as Map<String, dynamic>)).toList();
        }
        if (data is Map && data['servers'] is List) {
          return (data['servers'] as List).map((e) => _fromJson(e as Map<String, dynamic>)).toList();
        }
      }
    } catch (e) {
      debugPrint('[HTTP_DISCOVER] failed: $e');
    }
    return [];
  }

  Future<List<DiscoveredServer>> discoverBridgesMcast() async {
    // On native, bridges advertise via _http._tcp with txt bakedown-bridge
    // This is already handled by SmbDiscoveryRepository scanning _http._tcp
    // For web, we can't do mDNS, so we try common bridge URLs
    return [];
  }

  DiscoveredServer _fromJson(Map<String, dynamic> json) {
    return DiscoveredServer(
      name: json['name'] as String? ?? json['host'] as String? ?? 'Unknown',
      host: json['host'] as String? ?? json['name'] as String? ?? 'Unknown',
      port: json['port'] as int? ?? 445,
    );
  }

  Future<List<DiscoveredServer>> scanCommonBridges() async {
    // Try localhost and common gateway IPs for bridge
    final candidates = [
      'http://localhost:8787',
      'http://127.0.0.1:8787',
      'http://192.168.1.1:8787',
    ];
    final found = <DiscoveredServer>[];
    for (final url in candidates) {
      try {
        final resp = await _dio.get('$url/api/folders',
            options: Options(validateStatus: (_) => true)).timeout(const Duration(seconds: 2));
        if (resp.statusCode == 200) {
          found.add(DiscoveredServer(name: 'Bridge at $url', host: url, port: 8787));
        }
      } catch (_) {}
    }
    return found;
  }
}
