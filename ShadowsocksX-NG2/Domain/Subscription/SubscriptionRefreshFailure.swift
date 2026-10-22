import Foundation

/// 持久化的订阅失败白名单，不携带 URL、秘密或任意平台错误描述。
enum SubscriptionRefreshFailure: Error, Codable, Equatable, Sendable {
  enum TransportCategory: String, Codable, Equatable, Sendable {
    case timedOut, tls, connection, unknown
  }
  enum ContentTypeCategory: String, Codable, Equatable, Sendable {
    case missing, unsupported
  }
  enum RecordField: String, Codable, Equatable, Sendable {
    case address, port, method, password, identity
  }
  case invalidURL
  case unsupportedScheme
  case insecureRedirect
  case transport(TransportCategory)
  case httpStatus(code: Int)
  case contentType(ContentTypeCategory)
  case decodingFailure
  case unsupportedSchemaVersion
  case missingServers
  case recordValidation(index: Int, field: RecordField)
  case duplicateIdentity
  case commit
  case unknown
}

extension SubscriptionRefreshFailure {
  /// The only conversion point for transport failures entering durable state.
  static func from(fetchError: SubscriptionFetchError) -> Self {
    switch fetchError {
    case .invalidURL:
      .invalidURL
    case .unsupportedScheme:
      .unsupportedScheme
    case .insecureRedirect:
      .insecureRedirect
    case .transport(let detail):
      .transport(transportCategory(for: detail))
    case .httpStatus(let code):
      .httpStatus(code: code)
    case .contentType(let received):
      .contentType(received == nil ? .missing : .unsupported)
    }
  }

  /// The only conversion point for parser failures entering durable state.
  static func from(parseError: SubscriptionParseError) -> Self {
    switch parseError {
    case .decodingFailure:
      .decodingFailure
    case .unsupportedSchemaVersion:
      .unsupportedSchemaVersion
    case .missingServers:
      .missingServers
    case .recordValidation(let index, let reason):
      .recordValidation(index: index, field: recordField(for: reason))
    case .duplicateServerID:
      .duplicateIdentity
    }
  }

  private static func transportCategory(for detail: String) -> TransportCategory {
    let normalized = detail.lowercased()
    if normalized.contains("timedout") || normalized.contains("timeout") {
      return .timedOut
    }
    if normalized.contains("tls") || normalized.contains("secure") {
      return .tls
    }
    if normalized.contains("connection") || normalized.contains("network")
      || normalized.contains("cannotconnect")
    {
      return .connection
    }
    return .unknown
  }

  private static func recordField(for reason: String) -> RecordField {
    switch reason {
    case let value where value.contains("server_port"):
      .port
    case let value where value.contains("server"):
      .address
    case let value where value.contains("method"):
      .method
    case let value where value.contains("password"):
      .password
    case let value where value.contains("id"):
      .identity
    default:
      .identity
    }
  }
}
