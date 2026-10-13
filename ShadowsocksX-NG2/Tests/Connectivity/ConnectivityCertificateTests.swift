import Foundation
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct ConnectivityCertificateTests {
  @Test func HTTPSRejectsUntrustedCertificateThroughRequiredProxy() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let (cert, key) = try makeCertificate(in: root)
    let marker = root.appendingPathComponent("tls-error")
    let script = try writeProxyScript(in: root)
    let proxy = Process()
    let output = Pipe()
    proxy.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proxy.arguments = ["python3", script.path, cert.path, key.path, marker.path]
    proxy.standardOutput = output
    proxy.standardError = FileHandle.nullDevice
    try proxy.run()
    defer {
      if proxy.isRunning {
        proxy.terminate()
        proxy.waitUntilExit()
      }
    }
    var data = Data()
    while let byte = try output.fileHandleForReading.read(upToCount: 1), !byte.isEmpty {
      if byte == Data([10]) { break }
      data.append(byte)
    }
    let port = try #require(
      Int(
        (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    )
    let id = NodeID.fresh()
    let server = SslocalServerDocument(
      id: "test", server: "example.com", serverPort: 443,
      password: "test", method: "aes-256-gcm", plugin: nil, pluginOpts: nil)
    let module = ServerConnectivity(
      configuration: { _ in server },
      measure: { _, url, _ in
        await ConnectivityHTTPRequest().perform(url: url, proxyPort: port)
      })
    module.setURL(URL(string: "https://localhost/test")!)
    await module.wait(for: module.test([id]))
    #expect(module.history(for: id).first?.outcome == .network)
    #expect(FileManager.default.fileExists(atPath: marker.path))
    if FileManager.default.fileExists(atPath: marker.path) {
      let failure = try String(contentsOf: marker, encoding: .utf8)
      #expect(failure.contains("UNKNOWN_CA") || failure.contains("CERTIFICATE_UNKNOWN"))
    }
  }
  private func makeCertificate(in root: URL) throws -> (URL, URL) {
    let cert = root.appendingPathComponent("cert.pem")
    let key = root.appendingPathComponent("key.pem")
    let openssl = Process()
    openssl.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
    openssl.arguments = [
      "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key.path,
      "-out", cert.path, "-days", "1", "-subj", "/CN=localhost", "-addext",
      "subjectAltName=DNS:localhost",
    ]
    openssl.standardOutput = FileHandle.nullDevice
    openssl.standardError = FileHandle.nullDevice
    try openssl.run()
    openssl.waitUntilExit()
    #expect(openssl.terminationStatus == 0)
    return (cert, key)
  }

  private func writeProxyScript(in root: URL) throws -> URL {
    let script = root.appendingPathComponent("proxy.py")
    try """
    import socket, ssl, sys, pathlib
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(sys.argv[1], sys.argv[2])
    server = socket.socket()
    server.bind(('127.0.0.1', 0)); server.listen()
    print(server.getsockname()[1], flush=True)
    while True:
        connection, _ = server.accept()
        request = b''
        while b'\\r\\n\\r\\n' not in request:
            data = connection.recv(4096)
            if not data: break
            request += data
        if not request.startswith(b'CONNECT localhost:443 '):
            connection.close(); continue
        connection.sendall(b'HTTP/1.1 200 Connection Established\\r\\n\\r\\n')
        try:
            secured = context.wrap_socket(connection, server_side=True)
            secured.recv(4096)
            secured.sendall(b'HTTP/1.1 204 No Content\\r\\n\\r\\n')
            secured.close()
        except ssl.SSLError as error:
            pathlib.Path(sys.argv[3]).write_text(str(error))
            connection.close()
    """.write(to: script, atomically: true, encoding: .utf8)
    return script
  }

}
