import Combine
import Foundation

/// 激活命令的会话级反馈状态：pending 与最近一次命令反馈的单一持有者，
/// 首页目标树、侧栏右键与分组详情三个激活入口共用。单飞——pending 中忽略
/// 新命令，激活=切换目标，并发双击无语义。命令经目录工作流 seam 发出；
/// 意外错误记录 `.failed` 后原样上抛，内联/弹窗的呈现方式由各面自决。
/// 反馈事实类型化，文案只在呈现边经 AppPresentation 生成（`.failed` 的
/// message 同理，为呈现值而非事实值）。
@MainActor
final class ActivationFeedbackState: ObservableObject {
  /// 最近一次命令的反馈；新命令开始时清空，完成后保留至下一次命令。
  enum Feedback: Equatable {
    case activated(skippedInvalid: Int)
    case rejected(ActivationFailure)
    /// 意外错误的呈现文案（AppPresentation 边缘生成）。
    case failed(message: String)

    var isSuccess: Bool {
      if case .activated = self { return true }
      return false
    }
  }

  struct Completion: Equatable {
    let id = UUID()
    let targetID: NodeID
    let feedback: Feedback
    let completedAt: Date
  }

  @Published private(set) var completion: Completion?
  @Published private(set) var pendingTargetID: NodeID?
  @Published private(set) var feedback: Feedback?
  @Published private(set) var feedbackTargetID: NodeID?

  var isPending: Bool { pendingTargetID != nil }

  /// 唯一命令入口。返回命令 outcome，单飞忽略时返回 nil；意外错误记录
  /// `.failed` 后原样上抛（弹窗呈现的调用面在 call site catch）。
  @discardableResult
  func activate(
    _ id: NodeID, via workflow: CatalogWorkflow
  ) async throws -> ActivationCommandOutcome? {
    guard pendingTargetID == nil else { return nil }
    pendingTargetID = id
    feedbackTargetID = id
    feedback = nil
    completion = nil
    defer {
      completion = feedback.map { Completion(targetID: id, feedback: $0, completedAt: Date()) }
      pendingTargetID = nil
    }
    do {
      let outcome = try await workflow.activate(id)
      switch outcome {
      case .activated(let skippedInvalid):
        feedback = .activated(skippedInvalid: skippedInvalid)
      case .rejectedActivation(let failure):
        feedback = .rejected(failure)
      }
      return outcome
    } catch {
      feedback = .failed(message: AppPresentation.message(for: error))
      throw error
    }
  }
}
