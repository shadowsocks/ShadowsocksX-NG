import Foundation
import os

/// 统一日志（Unified Logging）最小发射单元：GUI、wrapper 与特权
/// helper 三个进程共用同一 subsystem，Console.app 一条过滤即可对照
/// 各进程事件。发射的事实（level/category/text/privateDetail）由调用方的
/// 封闭事件枚举给出；privacy 拆分口径与去向取舍见 ADR-0045，特权 helper
/// 的接入边界见 ADR-0047。
enum SystemLog {
  /// 系统日志 subsystem：各进程共用一个名字，Console.app 一条过滤全看。
  static let subsystem = "com.qiuyuzhou.ShadowsocksX-NG2"

  /// 统一日志写入开关（测试缝）：`SSXNG_SYSTEM_LOG=0` 关闭系统日志写入，
  /// stderr 行与事件缓冲不受影响。scheme 的测试动作注入该值，测试拉起的
  /// 子进程在夹具 env 显式设置——测试运行不把大量日志灌进系统日志 store。
  static let systemLogEnabled = isSystemLogEnabled(ProcessInfo.processInfo.environment)

  static func isSystemLogEnabled(_ environment: [String: String]) -> Bool {
    environment["SSXNG_SYSTEM_LOG"] != "0"
  }

  /// 按路由发射一条统一日志消息：公开文本标 public，自由 detail 段标
  /// private（普通视图显示 `<private>`）。写入开关关闭时整体跳过。
  static func emit(_ route: SystemLogRoute) {
    guard systemLogEnabled else { return }
    let logger = Logger(subsystem: subsystem, category: route.category)
    if let detail = route.privateDetail {
      logger.log(level: route.level, "\(route.text, privacy: .public)\(detail, privacy: .private)")
    } else {
      logger.log(level: route.level, "\(route.text, privacy: .public)")
    }
  }
}

/// 系统日志路由事实：发射缝按此构造统一日志消息。`text` 已含与
/// `privateDetail` 之间的分隔符，两者拼接等于事件的 `description`。
struct SystemLogRoute: Sendable {
  var level: OSLogType
  var category: String
  var text: String
  var privateDetail: String?
}
