import Foundation
import Testing

@testable import ShadowsocksX_NG2

struct SeparateListenerTests {
  @Test func terminalCommandsTreatPasswordAsUsableSecretWithoutReshaping() {
    var settings = ProxyListeningConfiguration(listenerMode: .allIPv4Interfaces)
    settings.lan.authenticationEnabled = true
    settings.lan.username = "user"
    // 契约 = 可用秘密：空密码等不合规形状不再被本层拒绝，只做百分号编码。
    let commands = TerminalProxyEnvironmentCommands(
      listen: RuntimeListenFacts(listen: settings),
      commandAddress: TerminalCommandAddress(
        bsdName: "en0", address: "192.0.2.2", displayName: "Wi-Fi"),
      password: { "" })
    #expect(commands.failure == nil)
    #expect(commands.zshBash.contains("http://user:@192.0.2.2:11089"))
    #expect(commands.zshBash.contains("socks5://user:@192.0.2.2:11088"))
  }

  @Test func newFormatsPreserveEncodedLANCredentialsAndBracketIPv6() {
    var settings = ProxyListeningConfiguration(listenerMode: .allIPv4AndIPv6Interfaces)
    settings.lan.authenticationEnabled = true
    settings.lan.username = "u @"
    let commands = TerminalProxyEnvironmentCommands(
      listen: RuntimeListenFacts(listen: settings),
      commandAddress: TerminalCommandAddress(
        bsdName: "en0", address: "2001:db8::2", displayName: "Wi-Fi"),
      password: { "p':@/$%!\"&^()" })
    let http = "http://u%20%40:p%27%3A%40%2F%24%25%21%22%26%5E%28%29@[2001:db8::2]:11089"
    #expect(commands.nushell.contains("$env.http_proxy = '\(http)'"))
    #expect(commands.windowsPowerShell.contains("$env:http_proxy = '\(http)'"))
    let cmdUserInfo = "u%~P20%~P40:p%~P27%~P3A%~P40%~P2F%~P24%~P25%~P21%~P22%~P26%~P5E%~P28%~P29"
    #expect(
      commands.windowsCMD
        == "for %P in (\"%\") do set \"http_proxy=http://\(cmdUserInfo)@[2001:db8::2]:11089\"\r\n"
        + "for %P in (\"%\") do set \"https_proxy=http://\(cmdUserInfo)@[2001:db8::2]:11089\"\r\n"
        + "for %P in (\"%\") do set \"all_proxy=socks5://\(cmdUserInfo)@[2001:db8::2]:11088\"\r\n"
        + "set \"no_proxy=localhost,127.0.0.1,::1,.local\"")
    #expect(commands.failure == nil)
  }

  @Test func windowsFormatsSetFourSessionVariablesUsingLANPorts() {
    let commands = TerminalProxyEnvironmentCommands(
      listen: RuntimeListenFacts(
        listen: ProxyListeningConfiguration(listenerMode: .allIPv4Interfaces)),
      commandAddress: TerminalCommandAddress(
        bsdName: "en0", address: "192.0.2.2", displayName: "Wi-Fi"))
    #expect(
      commands.windowsCMD == "set \"http_proxy=http://192.0.2.2:11089\" & "
        + "set \"https_proxy=http://192.0.2.2:11089\" & "
        + "set \"all_proxy=socks5://192.0.2.2:11088\" & "
        + "set \"no_proxy=localhost,127.0.0.1,::1,.local\"")
    #expect(
      commands.windowsPowerShell == "$env:http_proxy = 'http://192.0.2.2:11089'; "
        + "$env:https_proxy = 'http://192.0.2.2:11089'; "
        + "$env:all_proxy = 'socks5://192.0.2.2:11088'; "
        + "$env:no_proxy = 'localhost,127.0.0.1,::1,.local';")
  }

  @Test func nushellSetsFourSessionVariablesUsingLocalPorts() {
    let commands = TerminalProxyEnvironmentCommands(
      listen: RuntimeListenFacts(listen: ProxyListeningConfiguration()),
      commandAddress: TerminalCommandAddress(
        bsdName: "lo0", address: "127.0.0.1", displayName: "lo0"))
    #expect(
      commands.nushell == "$env.http_proxy = 'http://127.0.0.1:11087'; "
        + "$env.https_proxy = 'http://127.0.0.1:11087'; "
        + "$env.all_proxy = 'socks5://127.0.0.1:11086'; "
        + "$env.no_proxy = 'localhost,127.0.0.1,::1,.local';")
  }

  @Test func disabledIPv6ConfigurationRoundTripsWithoutAffectingEffectiveRuntime() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ProxyListeningFileStore(
      fileURL: directory.appendingPathComponent("proxy-listening.json"))
    var listen = ProxyListeningConfiguration()
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
    var listen = ProxyListeningConfiguration()
    listen.listenerMode = .allIPv4Interfaces
    #expect(listen.locals.count == 4)
    #expect(listen.locals.first?.localAddress == "127.0.0.1")
    #expect(listen.locals.first?.mode == "tcp_and_udp")
    #expect(listen.locals.last?.localPort == 11089)
  }

  @Test func oldSettingsFileIsIgnoredAndPreserved() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let oldURL = directory.appendingPathComponent("settings.json")
    let oldData = Data(
      #"{"localListen":{"socksPort":13001,"httpPort":13002},"agentEnabled":true}"#.utf8)
    try AtomicFileWriter.write(oldData, to: oldURL)
    let newURL = directory.appendingPathComponent(
      ProxyListeningFileStore.defaultFileURL().lastPathComponent)
    let store = ProxyListeningFileStore(fileURL: newURL)
    #expect(try store.load() == ProxyListeningConfiguration())
    try store.save(ProxyListeningConfiguration())
    #expect(try Data(contentsOf: oldURL) == oldData)
  }

  @Test func networkCommandUsesLANPorts() {
    let listen = ProxyListeningConfiguration(listenerMode: .allIPv4Interfaces)
    let commands = TerminalProxyEnvironmentCommands(
      listen: RuntimeListenFacts(listen: listen),
      commandAddress: TerminalCommandAddress(
        bsdName: "en0", address: "192.0.2.2", displayName: "Wi-Fi"))
    #expect(commands.zshBash.contains("http://192.0.2.2:11089"))
    #expect(commands.fish.contains("socks5://192.0.2.2:11088"))
  }

  @Test func authenticationEncodesSpecialCharactersAndNeverReadsPasswordForLocalCommands() {
    var settings = ProxyListeningConfiguration(listenerMode: .allIPv4AndIPv6Interfaces)
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
    var settings = ProxyListeningConfiguration(listenerMode: .allIPv6Interfaces)
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
    let store = RuntimeFileStore(fileURL: directory.appendingPathComponent("sslocal-active.json"))
    try store.write(document)
    let snapshot = try #require(RuntimePublication.load(at: store.supervisionFileURL))
    let paths = snapshot.authenticationFiles.map { directory.appendingPathComponent($0).path }
    let http =
      try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: paths[1])))
      as? [String: Any]
    #expect(http?["basic"] != nil)
    for path in paths {
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
    var settings = ProxyListeningConfiguration()
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
    let settings = ProxyListeningConfiguration(listenerMode: .allIPv6Interfaces)
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
