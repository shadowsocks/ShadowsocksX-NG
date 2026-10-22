import AgeSwift
import Foundation
import Security
import Testing

@testable import ShadowsocksX_NG2

struct AgeConfigurationStorageTests {
  @Test(arguments: [false, true])
  func standardCLIReadsAppFilesAndAppReadsBinaryAndArmor(listening: Bool) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let keys = TestLibraryKeys()
    let url = directory.appendingPathComponent(listening ? "proxy-listening.age" : "catalog.age")
    let library = CatalogFileStore(fileURL: url, library: ServerLibraryStorage(keys: keys))
    let listeners = ProxyListeningFileStore(fileURL: url, keys: keys)
    if listening {
      var configuration = try listeners.load()
      configuration.lan.password = "CLI-INTEROP-SECRET"
      try listeners.save(configuration)
    } else {
      var document = try library.load()
      _ = try document.catalog.addGroup("CLI-INTEROP-SECRET")
      try library.save(document)
    }
    let identityData = try #require(keys.values.values.first)
    let identity = try AgeIdentity(string: #require(String(data: identityData, encoding: .utf8)))
    let identityURL = directory.appendingPathComponent("identity.txt")
    try AtomicFileWriter.write(identityData + Data("\n".utf8), to: identityURL)
    let jsonURL = directory.appendingPathComponent("payload.json")
    try runAge(["-d", "-i", identityURL.path, "-o", jsonURL.path, url.path])
    let payload = try Data(contentsOf: jsonURL)
    #expect(payload.range(of: Data("CLI-INTEROP-SECRET".utf8)) != nil)
    for armor in [false, true] {
      let output = directory.appendingPathComponent(armor ? "cli-armored.age" : "cli-binary.age")
      try runAge(
        ["-e", "-r", identity.recipient.serialized, "-o", output.path]
          + (armor ? ["-a"] : []) + [jsonURL.path])
      try Data(contentsOf: output).write(to: url)
      if listening {
        let reopened = ProxyListeningFileStore(fileURL: url, keys: keys)
        let configuration = try reopened.load()
        #expect(configuration.lan.password == "CLI-INTEROP-SECRET")
        try reopened.save(configuration)
      } else {
        let reopened = CatalogFileStore(fileURL: url, library: ServerLibraryStorage(keys: keys))
        let document = try reopened.load()
        #expect(document.catalog.entries.values.first?.displayName == "CLI-INTEROP-SECRET")
        try reopened.save(document)
      }
      #expect(try Data(contentsOf: url).starts(with: Data("age-encryption.org/v1\n".utf8)))
      #expect(keys.values.count == 1)
    }
  }

  @Test(arguments: ["catalog.enc", "catalog.json", "proxy-listening.enc", "proxy-listening.json"])
  func historicalFilesRequireExplicitReset(name: String) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let oldURL = directory.appendingPathComponent(name)
    let old = Data("unsupported historical configuration".utf8)
    try old.write(to: oldURL)
    let keys = TestLibraryKeys()
    if name.hasPrefix("catalog") {
      let store = CatalogFileStore(
        fileURL: directory.appendingPathComponent("catalog.age"),
        library: ServerLibraryStorage(keys: keys))
      #expect(throws: EncryptedFileError.unsupportedVersion) { try store.load() }
      #expect(keys.values.isEmpty)
      _ = try store.reset()
      #expect(
        try CatalogFileStore(fileURL: store.fileURL, library: ServerLibraryStorage(keys: keys))
          .load().catalog.isEmpty)
    } else {
      let store = ProxyListeningFileStore(
        fileURL: directory.appendingPathComponent("proxy-listening.age"), keys: keys)
      #expect(throws: ProxyListeningStoreError.encryptedFile(.unsupportedVersion)) {
        try store.load()
      }
      #expect(keys.values.isEmpty)
      _ = try store.reset()
      #expect(
        try ProxyListeningFileStore(fileURL: store.fileURL, keys: keys).load()
          == ProxyListeningConfiguration())
    }
    #expect(try Data(contentsOf: oldURL) == old)
  }

  @Test func inaccessibleAndUnrelatedIdentitiesDoNotBlockTheMatchingIdentity() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let keys = TestLibraryKeys()
    let url = directory.appendingPathComponent("catalog.age")
    let original = CatalogFileStore(fileURL: url, library: ServerLibraryStorage(keys: keys))
    _ = try original.load()
    let identity = try #require(keys.values.values.first)
    let blocked = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let unrelated = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let matching = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
    keys.values = [
      blocked: identity, unrelated: Data(try AgeIdentity.generate().serialized.utf8),
      matching: identity,
    ]
    keys.blockedIDs = [blocked]
    let reopened = CatalogFileStore(fileURL: url, library: ServerLibraryStorage(keys: keys))
    var document = try reopened.load()
    _ = try document.catalog.addGroup("matching identity")
    try reopened.save(document)
    keys.values = [matching: identity]
    #expect(
      try CatalogFileStore(fileURL: url, library: ServerLibraryStorage(keys: keys)).load()
        == document)
  }

  @Test(arguments: [false, true])
  func failedFileCommitAfterIdentityCreationPreservesThePreviousConfiguration(listening: Bool)
    throws
  {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      if let files = try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)
      {
        for file in files {
          try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: file.path)
        }
      }
      try? FileManager.default.removeItem(at: directory)
    }
    let keys = TestLibraryKeys()
    let url = directory.appendingPathComponent(listening ? "proxy-listening.age" : "catalog.age")
    let library = CatalogFileStore(fileURL: url, library: ServerLibraryStorage(keys: keys))
    let listeners = ProxyListeningFileStore(fileURL: url, keys: keys)
    if listening { _ = try listeners.load() } else { _ = try library.load() }
    let original = try Data(contentsOf: url)
    try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: url.path)
    #expect(throws: (any Error).self) {
      if listening { _ = try listeners.reset() } else { _ = try library.reset() }
    }
    #expect(keys.values.count == 2)
    #expect(try Data(contentsOf: url) == original)
    try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: url.path)
    if listening {
      #expect(
        try ProxyListeningFileStore(fileURL: url, keys: keys).load()
          == ProxyListeningConfiguration())
    } else {
      #expect(
        try CatalogFileStore(fileURL: url, library: ServerLibraryStorage(keys: keys))
          .load().catalog.isEmpty)
    }
  }

  @Test(arguments: [
    "unknown-version", "invalid-listener", "oversized", "oversized-file", "truncated",
  ])
  func invalidListeningPayloadCannotReplaceCommittedConfiguration(failure: String) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let keys = TestLibraryKeys()
    let url = directory.appendingPathComponent("proxy-listening.age")
    let store = ProxyListeningFileStore(fileURL: url, keys: keys)
    _ = try store.load()
    let identityData = try #require(keys.values.values.first)
    let identityText = try #require(String(data: identityData, encoding: .utf8))
    let identity = try AgeIdentity(string: identityText)
    let original = try Data(contentsOf: url)
    var json = try #require(
      JSONSerialization.jsonObject(with: Age.decrypt(original, identities: [identity]))
        as? [String: Any])
    switch failure {
    case "unknown-version": json["version"] = 999
    case "invalid-listener":
      var configuration = try #require(json["configuration"] as? [String: Any])
      var local = try #require(configuration["local"] as? [String: Any])
      local["socksPort"] = 0
      configuration["local"] = local
      json["configuration"] = configuration
    case "oversized": json["padding"] = String(repeating: "x", count: 1024 * 1024)
    default: break
    }
    var ciphertext = try Age.encrypt(
      JSONSerialization.data(withJSONObject: json), recipients: [identity.recipient])
    if failure == "truncated" { ciphertext.removeLast() }
    if failure == "oversized-file" { ciphertext = Data(repeating: 0, count: 2 * 1024 * 1024) }
    try ciphertext.write(to: url)
    let reopened = ProxyListeningFileStore(fileURL: url, keys: keys)
    #expect(throws: (any Error).self) { try reopened.load() }
    #expect(throws: (any Error).self) { try reopened.save(ProxyListeningConfiguration()) }
    #expect(try Data(contentsOf: url) == ciphertext)
    try original.write(to: url)
    var tooLarge = try store.load()
    tooLarge.lan.password = String(repeating: "x", count: 1024 * 1024)
    #expect(throws: ProxyListeningStoreError.encryptedFile(.malformedFile)) {
      try store.save(tooLarge)
    }
    #expect(try Data(contentsOf: url) == original)
  }

  @Test func realKeychainIdentityCanBeEnumeratedAndReopenedWithoutInteraction() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let keys = KeychainMasterKeyStore(namespace: "age-tests.\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: directory)
      cleanUpKeychainItems(for: keys)
    }
    let url = directory.appendingPathComponent("catalog.age")
    let store = CatalogFileStore(fileURL: url, library: ServerLibraryStorage(keys: keys))
    let document = try store.load()
    let ids = try keys.ids()
    #expect(ids.count == 1)
    let id = try #require(ids.first)
    let data = try #require(try keys.read(id, allowingInteraction: false))
    #expect(data.starts(with: Data("AGE-SECRET-KEY-1".utf8)))
    #expect(
      try CatalogFileStore(fileURL: url, library: ServerLibraryStorage(keys: keys)).load()
        == document)
    _ = try store.reset()
    #expect(try keys.ids().count == 2)
    #expect(
      try CatalogFileStore(fileURL: url, library: ServerLibraryStorage(keys: keys))
        .load().catalog.isEmpty)
  }

  private func runAge(_ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["age"] + arguments
    // Xcode test runners do not inherit the interactive shell's Homebrew PATH.
    process.environment = ProcessInfo.processInfo.environment.merging([
      "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
    ]) { _, value in value }
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    guard process.terminationStatus == 0 else { throw EncryptedFileError.malformedFile }
  }

  private func cleanUpKeychainItems(for keys: KeychainMasterKeyStore) {
    let ids = try? keys.ids()
    #expect(ids != nil, "读取测试 Keychain 项时清理失败")
    for id in ids ?? [] {
      let status = SecItemDelete(
        [
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: keys.service,
          kSecAttrAccount as String: id.uuidString,
          kSecAttrSynchronizable as String: false,
          kSecUseDataProtectionKeychain as String: false,
        ] as CFDictionary)
      #expect(
        status == errSecSuccess || status == errSecItemNotFound,
        "删除测试 Keychain 项失败：\(status)")
    }
    let remainingIDs = try? keys.ids()
    #expect(remainingIDs?.isEmpty == true, "测试 Keychain 项未清理干净")
  }
}
