import Foundation
import Security

/// 仅包含错误类别与系统状态码，不携带服务器资料或路径。
enum ServerLibraryFailure: Equatable {
  case authorization(OSStatus)
  case keyUnavailable
  case authenticationFailed
  case unsupportedVersion
  case malformedFile
  case storage

  init(_ error: Error) {
    switch error {
    case MasterKeyStoreError.keychainStatus(let status): self = .authorization(status)
    case ServerLibraryError.keyUnavailable: self = .keyUnavailable
    case ServerLibraryError.authenticationFailed: self = .authenticationFailed
    case ServerLibraryError.unsupportedVersion: self = .unsupportedVersion
    case ServerLibraryError.malformedFile: self = .malformedFile
    case CatalogFileStore.PersistenceError.corrupt: self = .malformedFile
    default: self = .storage
    }
  }
}
