import Foundation
import ServiceManagement
import SwiftUI

enum LoginItemStatus: Equatable, Sendable {
  case notRegistered
  case registered
  case requiresApproval
  case notFound
}

protocol LaunchAtLoginControlling {
  var status: LoginItemStatus { get }
  func register() throws
  func unregister() throws
}

struct SMAppLaunchAtLoginService: LaunchAtLoginControlling {
  private let service = SMAppService.mainApp

  var status: LoginItemStatus {
    switch service.status {
    case .notRegistered:
      .notRegistered
    case .enabled:
      .registered
    case .requiresApproval:
      .requiresApproval
    case .notFound:
      .notFound
    @unknown default:
      .notFound
    }
  }

  func register() throws {
    try service.register()
  }

  func unregister() throws {
    try service.unregister()
  }
}

/// Owns the GUI login-item intent independently from the proxy LaunchAgent.
/// The system's login-item registration is the only source of truth: the
/// toggle is off until the user enables it, and enabling or disabling only
/// issues the corresponding system call before re-reading the status.
@MainActor
final class LaunchAtLoginController: ObservableObject {
  @Published private(set) var status: LoginItemStatus
  @Published private(set) var errorMessage: String?

  private let service: LaunchAtLoginControlling

  init(service: LaunchAtLoginControlling = SMAppLaunchAtLoginService()) {
    self.service = service
    status = service.status
  }

  /// 已注册或已请求注册待批准都算开启——两者都只来自系统 API 的状态。
  var isEnabled: Bool {
    status == .registered || status == .requiresApproval
  }

  var requiresApproval: Bool { status == .requiresApproval }

  func setEnabled(_ enabled: Bool) {
    do {
      if enabled {
        try service.register()
      } else {
        try service.unregister()
      }
      errorMessage = nil
    } catch {
      errorMessage = error.presentableMessage
    }
    status = service.status
  }
}
