class DiscoveredServer {
  final String name;
  final String host;
  final int port;
  final String? share;
  final bool isShare;

  const DiscoveredServer({
    required this.name,
    required this.host,
    this.port = 445,
    this.share,
    this.isShare = false,
  });

  String get displayShare => share ?? '';
  String get uncPath => share != null ? '\\\\$host\\$share' : host;
}
