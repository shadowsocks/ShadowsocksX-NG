import Foundation
import Testing

@testable import ShadowsocksX_NG2

struct SeparateListenerTests {
  @Test func disabledIPv6ConfigurationRoundTripsWithoutAffectingEffectiveRuntime() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ListenSettingsFileStore(fileURL: directory.appendingPathComponent("listen.json"))
    var listen = SslocalListenSettings()
    listen.lan.mode = .allIPv6Interfaces
    listen.lan.authenticationEnabled = true
    listen.lan.passwordReference = "saved-reference"
    try store.save(listen)
    let restored = try store.load()
    #expect(!restored.lan.isEnabled)
    #expect(restored.lan.mode == .allIPv6Interfaces)
    #expect(restored.lan.passwordReference == "saved-reference")
    let document = SslocalRuntimeDocument(servers: [], listen: restored)
    #expect(document.locals.count == 2)
    #expect(document.ipv6Only == nil)
    #expect(document.isWellFormed)
    #expect(SslocalRuntimeDocument.decodeValidated(try document.jsonData()) != nil)
    #expect(
      PortOccupancyProbeRequest(endpoint: .socks, listen: RuntimeListenFacts(listen: restored))
        .bindAddress == "127.0.0.1")
  }

  @Test func enablingLANPreservesLocalListeners() {
    var listen = SslocalListenSettings()
    listen.listenerMode = .allIPv4Interfaces
    #expect(listen.locals.count == 4)
    #expect(listen.locals.first?.localAddress == "127.0.0.1")
    #expect(listen.locals.first?.mode == "tcp_and_udp")
    #expect(listen.locals.last?.localPort == 11089)
  }

  @Test func oldListenerPreferencesUseDefaultsWithoutResettingOtherPreferences() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("settings.json")
    try AtomicFileWriter.write(
      Data(
        #"{"socksPort":13001,"httpPort":13002,"listenerMode":"all_ipv4_interfaces","proxyExceptions":"example.com"}"#
          .utf8), to: url)
    let settings = try ProxySettingsFileStore(fileURL: url).load()
    #expect(settings.listen.socksPort == 11086)
    #expect(settings.listen.listenerMode == .disabled)
    #expect(settings.proxyExceptions == "example.com")
  }

  @Test func networkCommandUsesLANPorts() {
    let listen = SslocalListenSettings(listenerMode: .allIPv4Interfaces)
    let commands = TerminalProxyEnvironmentCommands(
      listen: RuntimeListenFacts(listen: listen),
      commandAddress: TerminalCommandAddress(
        bsdName: "en0", address: "192.0.2.2", displayName: "Wi-Fi"))
    #expect(commands.zshBash.contains("http://192.0.2.2:11089"))
    #expect(commands.fish.contains("socks5://192.0.2.2:11088"))
  }

  @Test func authenticationEncodesSpecialCharactersAndNeverReadsPasswordForLocalCommands() {
    var settings = SslocalListenSettings(listenerMode: .allIPv4AndIPv6Interfaces)
    settings.lan.authenticationEnabled = true
    settings.lan.username = "u @"
    let facts = RuntimeListenFacts(listen: settings)
    let commands = TerminalProxyEnvironmentCommands(
      listen: facts,
      commandAddress: TerminalCommandAddress(
        bsdName: "en0", address: "2001:db8::2", displayName: "Wi-Fi"),
      password: { "p':@/$" })
    #expect(commands.zshBash.contains("http://u%20%40:p%27%3A%40%2F%24@[2001:db8::2]:11089"))
    #expect(commands.fish.contains("socks5://u%20%40:p%27%3A%40%2F%24@[2001:db8::2]:11088"))
    #expect(commands.failure == nil)
    let local = TerminalProxyEnvironmentCommands(
      listen: facts,
      commandAddress: TerminalCommandAddress(
        bsdName: "lo0", address: "127.0.0.1", displayName: "lo0"),
      password: {
        Issue.record("本地命令不得读取局域网密码")
        return ""
      })
    #expect(local.zshBash.contains("http://127.0.0.1:11087"))
    #expect(local.failure == nil)
    let unavailable = TerminalProxyEnvironmentCommands(
      listen: facts,
      commandAddress: TerminalCommandAddress(
        bsdName: "en0", address: "2001:db8::2", displayName: "Wi-Fi"))
    #expect(unavailable.failure == .credentialUnreadable)
    #expect(unavailable.zshBash.isEmpty)
  }

  @Test func runtimeAuthenticationCreatesProtectedFilesAndRotatingPasswordChangesFingerprint()
    throws
  {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var settings = SslocalListenSettings(listenerMode: .allIPv6Interfaces)
    settings.lan.authenticationEnabled = true
    let base = SslocalRuntimeDocument(servers: [], listen: settings)
    #expect(!base.isWellFormed)
    let auth = RuntimeListenerAuthentication(
      username: "user", password: "password01", directory: directory.path)
    let document = base.authenticatingLAN(auth)
    #expect(document.isWellFormed)
    #expect(document.locals[0].socks5AuthConfigPath == nil)
    #expect(document.locals[2].socks5AuthConfigPath == auth.socksPath)
    #expect(document.locals[3].httpAuthConfigPath == auth.httpPath)
    try auth.writeFiles()
    let http =
      try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: auth.httpPath)))
      as? [String: Any]
    #expect(http?["basic"] != nil)
    for path in [auth.socksPath, auth.httpPath] {
      let permissions =
        try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
      #expect(permissions == 0o600)
    }
    let rotated = base.authenticatingLAN(
      RuntimeListenerAuthentication(
        username: "user", password: "password02", directory: directory.path))
    #expect(document.listenFingerprint != rotated.listenFingerprint)
    let json = try #require(String(data: try document.jsonData(), encoding: .utf8))
    #expect(!json.contains("local_udp_port"))
  }

  @Test func disabledLANStillParticipatesInFourPortValidation() {
    var settings = SslocalListenSettings()
    settings.lan.socksPort = 11086
    #expect(
      settings.portValidationErrors().contains(
        .duplicatePort(endpoint: .socks, otherEndpoint: .lanSocks, port: 11086)))
    settings.lan.socksPort = 1024
    #expect(
      settings.portValidationErrors().contains(.portOutOfRange(endpoint: .lanSocks, port: 1024)))
    settings.lan.socksPort = 1025
    #expect(settings.portValidationErrors().isEmpty)
  }

  @Test func portProbeRequestsDistinguishLocalAndIPv6LANBindings() {
    let settings = SslocalListenSettings(listenerMode: .allIPv6Interfaces)
    let facts = RuntimeListenFacts(listen: settings)
    let local = PortOccupancyProbeRequest(endpoint: .socks, listen: facts)
    let lan = PortOccupancyProbeRequest(endpoint: .lanSocks, listen: facts)
    #expect(local.bindAddress == "127.0.0.1")
    #expect(local.port == 11086)
    #expect(lan.bindAddress == "::")
    #expect(lan.port == 11088)
    #expect(lan.listenerMode.ipv6Only == true)
  }
}
