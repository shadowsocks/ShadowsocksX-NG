import Darwin
import Foundation

/// 本地端点健康探测：进程存在不等于代理可用——激活后以
/// TCP 连接确认 sslocal 实际完成监听绑定。探测只做客户端 connect，不建立
/// 带复用选项的监听 socket（Legacy 的 reuse-port 残留假成功在此构造上不可
/// 复现）；失败详情供「启动失败」点名端点与端口。
enum EndpointHealthProbe {
  enum Outcome: Equatable {
    case reachable
    /// 立即失败（连接被拒、地址不可达等），携带系统层原因。
    case refused(detail: String)
    /// 超时内未完成连接。
    case timedOut
  }

  static func probe(host: String, port: Int, timeout: TimeInterval) -> Outcome {
    var hints = addrinfo()
    hints.ai_family = AF_UNSPEC
    hints.ai_socktype = SOCK_STREAM
    hints.ai_protocol = IPPROTO_TCP
    var info: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, String(port), &hints, &info) == 0, let first = info else {
      return .refused(detail: "监听地址无法解析")
    }
    defer { freeaddrinfo(info) }

    var lastFailure: Outcome?
    for candidate in sequence(first: first, next: { $0.pointee.ai_next }) {
      let descriptor = socket(
        candidate.pointee.ai_family, candidate.pointee.ai_socktype, candidate.pointee.ai_protocol)
      guard descriptor >= 0 else { continue }
      defer { close(descriptor) }

      let previousFlags = fcntl(descriptor, F_GETFL, 0)
      _ = fcntl(descriptor, F_SETFL, previousFlags | O_NONBLOCK)
      if connect(descriptor, candidate.pointee.ai_addr, candidate.pointee.ai_addrlen) == 0 {
        return .reachable
      }
      guard errno == EINPROGRESS else {
        lastFailure = .refused(detail: String(cString: strerror(errno)))
        continue
      }
      var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
      let pollResult = poll(&pollDescriptor, 1, Int32(timeout * 1000))
      guard pollResult > 0 else {
        lastFailure = lastFailure ?? .timedOut
        continue
      }
      var socketError: Int32 = 0
      var length = socklen_t(MemoryLayout<Int32>.size)
      getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &length)
      if socketError == 0 {
        return .reachable
      }
      lastFailure = .refused(detail: String(cString: strerror(socketError)))
    }
    return lastFailure ?? .refused(detail: "无法建立连接")
  }
}
