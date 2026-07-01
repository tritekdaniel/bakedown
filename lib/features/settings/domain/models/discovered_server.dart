class DiscoveredServer {
  final String name;
  final String host;
  final int port;

  const DiscoveredServer({
    required this.name,
    required this.host,
    this.port = 445,
  });
}
