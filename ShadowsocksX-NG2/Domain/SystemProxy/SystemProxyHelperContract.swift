import Foundation

/// GUI 与特权系统代理 helper 的共享 XPC 契约。类型同时编入 GUI、
/// helper 与测试 target；payload 以 JSON 编码保持 closed typed 语义。
@objc protocol SystemProxyHelperControlling {
  /// 应用 closed typed 配置到活动网络位置的每个服务。
  func apply(_ payload: Data, withReply reply: @escaping (Data) -> Void)
  /// 无条件清除全部网络位置全部服务的完整 Proxies 字典。
  func clear(withReply reply: @escaping (Data) -> Void)
}

/// helper 的固定身份：MachService 名、LaunchDaemon plist 名与客户端校验基准。
/// 客户端只按 2.0 的 bundle identifier（代码签名 identifier）接受，不限
/// Team ID 或账号。
enum SystemProxyHelperIdentity {
  static let machServiceName = "com.qiuyuzhou.ShadowsocksX-NG2.systemproxy"
  static let plistName = "com.qiuyuzhou.ShadowsocksX-NG2.systemproxy.plist"
  static let launchdLabel = "com.qiuyuzhou.ShadowsocksX-NG2.systemproxy"
  static let clientCodeSigningIdentifier = "com.qiuyuzhou.ShadowsocksX-NG2"

  /// App bundle 内 LaunchDaemon 清单内容（注册漂移指纹的基准）。helper 进程
  /// 内没有 bundle，返回 nil，调用方按「无基准不动作」处理。Contents/Library
  /// 不是资源目录，Bundle 资源 API 搜不到，按固定路径直读。bundle 参数生产
  /// 默认 Bundle.main；去宿主化（ADR 0021）后单测经控制器的 appBundle 缝注入
  /// 构建产物 bundle。
  static func launchDaemonPlistData(in bundle: Bundle = .main) -> Data? {
    let url = bundle.bundleURL
      .appendingPathComponent("Contents/Library/LaunchDaemons")
      .appendingPathComponent(plistName)
    return try? Data(contentsOf: url)
  }
}

/// helper XPC 应答：成功携带 typed 结果，失败携带 typed 错误族。
enum SystemProxyHelperResponse: Equatable, Sendable, Codable {
  case applied(SystemProxyWriteOutcome)
  case cleared
  case failure(SystemProxyError)
}

enum SystemProxyHelperWireError: Error, Equatable, Sendable {
  case undecodableResponse(String)
}

enum SystemProxyHelperWire {
  /// SystemProxyHelperResponse 全部由简单可编码类型组成，JSON 编码不可失败；
  /// 若未来加入不可编码载荷，显式失败好过发出无法解码的应答。
  static func encode(_ response: SystemProxyHelperResponse) -> Data {
    do {
      return try JSONEncoder().encode(response)
    } catch {
      preconditionFailure("system proxy helper response encode failed: \(error)")
    }
  }

  static func decode(_ payload: Data) throws -> SystemProxyHelperResponse {
    do {
      return try JSONDecoder().decode(SystemProxyHelperResponse.self, from: payload)
    } catch {
      throw SystemProxyHelperWireError.undecodableResponse(String(describing: error))
    }
  }

  static func encodeConfiguration(_ configuration: SystemProxyConfiguration) throws -> Data {
    try JSONEncoder().encode(configuration)
  }

  static func decodeConfiguration(_ payload: Data) throws -> SystemProxyConfiguration {
    do {
      return try JSONDecoder().decode(SystemProxyConfiguration.self, from: payload)
    } catch {
      throw SystemProxyError.invalidRequest(String(describing: error))
    }
  }
}
