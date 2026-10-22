enum PluginTransportMode: String, Codable, CaseIterable, Sendable {
  case tcpOnly = "tcp_only"
  case tcpAndUDP = "tcp_and_udp"
}
