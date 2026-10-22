import Darwin
import Foundation

/// Test-owned UDP DNS: A records point at the local echo service; AAAA has no data.
/// This keeps domain ACL probes independent of system DNS and external networking.
final class LoopbackDNSResponder {
  private let descriptor: Int32
  let port: Int

  init() throws {
    let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
    guard descriptor >= 0 else { throw POSIXError(.ENOTSOCK) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bound == 0 else {
      close(descriptor)
      throw POSIXError(.EADDRINUSE)
    }
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let named = withUnsafeMutablePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        getsockname(descriptor, $0, &length)
      }
    }
    guard named == 0 else {
      close(descriptor)
      throw POSIXError(.EINVAL)
    }
    self.descriptor = descriptor
    port = Int(UInt16(bigEndian: address.sin_port))
    DispatchQueue.global().async {
      while true {
        var packet = [UInt8](repeating: 0, count: 4096)
        var peer = sockaddr_storage()
        var peerLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let received = withUnsafeMutablePointer(to: &peer) {
          $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            recvfrom(descriptor, &packet, packet.count, 0, $0, &peerLength)
          }
        }
        guard received > 0 else { return }
        guard let response = Self.response(to: Array(packet.prefix(received))) else { continue }
        response.withUnsafeBytes { buffer in
          withUnsafePointer(to: &peer) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
              _ = sendto(descriptor, buffer.baseAddress, buffer.count, 0, $0, peerLength)
            }
          }
        }
      }
    }
  }

  deinit {
    shutdown(descriptor, SHUT_RDWR)
    close(descriptor)
  }

  private static func response(to query: [UInt8]) -> [UInt8]? {
    guard query.count >= 17, query[4...5].elementsEqual([0, 1]) else { return nil }
    var end = 12
    while end < query.count, query[end] != 0 {
      let length = Int(query[end])
      guard length <= 63 else { return nil }
      end += length + 1
    }
    guard end + 5 <= query.count else { return nil }
    let isIPv4 = query[end + 1...end + 4].elementsEqual([0, 1, 0, 1])
    var result = Array(query.prefix(end + 5))
    result[2] = 0x81
    result[3] = 0x80
    result[6] = 0
    result[7] = isIPv4 ? 1 : 0
    result[8...11] = [0, 0, 0, 0]
    if isIPv4 {
      result += [0xc0, 0x0c, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 127, 0, 0, 1]
    }
    return result
  }
}
