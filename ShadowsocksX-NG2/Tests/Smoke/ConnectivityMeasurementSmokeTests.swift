import Foundation
import Testing

@testable import ShadowsocksX_NG2

/// Real sslocal forwards a fixed-address HTTP probe to a local, unencrypted
/// Shadowsocks fixture. This checks process/protocol wiring, not remote egress.
@MainActor
struct ConnectivityMeasurementSmokeTests {
  @Test func realSslocalPreservesHostForCandidateAndThreeSamplesThenCleansUp() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let script = root.appendingPathComponent("fixture.py")
    let requests = root.appendingPathComponent("requests.jsonl")
    try """
    import socket, sys, threading, json
    server = socket.socket()
    server.bind(('127.0.0.1', 0)); server.listen()
    print(server.getsockname()[1], flush=True)
    lock = threading.Lock()
    def read(connection, size):
        result = b''
        while len(result) < size:
            data = connection.recv(size - len(result))
            if not data: raise EOFError()
            result += data
        return result
    def serve(connection):
        try:
            atyp = read(connection, 1)[0]
            if atyp == 1: address = socket.inet_ntop(socket.AF_INET, read(connection, 4))
            elif atyp == 4: address = socket.inet_ntop(socket.AF_INET6, read(connection, 16))
            else: address = read(connection, read(connection, 1)[0]).decode()
            port = int.from_bytes(read(connection, 2), 'big')
            request = b''
            while b'\\r\\n\\r\\n' not in request:
                request += read(connection, 1)
            with lock:
                with open(sys.argv[1], 'a') as output:
                    output.write(json.dumps({'address': address, 'port': port, 'request': request.decode()}) + '\\n')
            connection.sendall(b'HTTP/1.1 204 No Content\\r\\n\\r\\n')
        finally: connection.close()
    while True:
        connection, _ = server.accept()
        threading.Thread(target=serve, args=(connection,), daemon=True).start()
    """.write(to: script, atomically: true, encoding: .utf8)
    let fixture = Process()
    fixture.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    fixture.arguments = ["python3", script.path, requests.path]
    let output = Pipe()
    fixture.standardOutput = output
    fixture.standardError = FileHandle.nullDevice
    try fixture.run()
    defer {
      fixture.terminate()
      fixture.waitUntilExit()
    }
    var line = Data()
    while let byte = try output.fileHandleForReading.read(upToCount: 1), byte != Data([10]),
      !byte.isEmpty
    {
      line.append(byte)
    }
    let portText = try #require(String(data: line, encoding: .utf8))
    let port = try #require(Int(portText))
    let environments = root.appendingPathComponent("environments")
    let runtime = ConnectivityRuntime(
      executable: AppArtifact.bundleURL.appendingPathComponent("Contents/Helpers/sslocal"),
      measurement: ConnectivityMeasurement(resolve: { _, _, _ in ["192.0.2.1"] }),
      temporaryRoot: environments)
    let server = SslocalServerDocument(
      id: "fixture", server: "127.0.0.1", serverPort: port, password: "fixture",
      method: "none", plugin: nil, pluginOpts: nil)
    let outcome = await runtime.measure(
      server, url: URL(string: "http://target.invalid:8080/check?token=private")!,
      preparationDeadline: .now.advanced(by: .seconds(30)))
    guard case .success = outcome else {
      Issue.record("Expected success through real sslocal: \(outcome)")
      return
    }
    let lines = try String(contentsOf: requests, encoding: .utf8).split(separator: "\n")
    #expect(lines.count == 4)
    for line in lines {
      let request = try #require(
        try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
      #expect(request["address"] as? String == "192.0.2.1")
      #expect(request["port"] as? Int == 8080)
      let http = try #require(request["request"] as? String)
      #expect(http.lowercased().contains("host: target.invalid:8080\r\n"))
      #expect(http.contains("/check?token=private"))
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: environments.path).isEmpty)
  }
}
