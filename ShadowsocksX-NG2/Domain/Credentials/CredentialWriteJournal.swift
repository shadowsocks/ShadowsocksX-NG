import Foundation

/// 凭据回滚的结构化结果：回滚是尽力恢复，存储失败不二次上抛，残局经此
/// 显式报出。纯数据、不含用户可见文案（文案归 presentation edge）。
enum CredentialRollbackOutcome: Equatable, Sendable {
  /// 本次未触碰任何凭据引用，无需恢复。
  case nothingToRestore
  /// 全部触碰过的引用恢复成功（集合非空）。
  case restored(Set<CredentialReference>)
  /// 尽力恢复后的残局：旧值继续生效的不变量被存储失败违例，未能恢复的
  /// 引用点名在 `failed`。
  case partial(restored: Set<CredentialReference>, failed: Set<CredentialReference>)
}

/// 凭据写入日志：目录文件只有在全部凭据写入成功后才替换；如果任何凭据或
/// 目录写入失败，则恢复改动前的每个引用值，避免旧秘密被覆盖或丢失。
///
/// 回滚是 best-effort：单个引用恢复失败不中断其余引用，残局经
/// `CredentialRollbackOutcome` 报出。写入期 `delete` 同样尽力而为——删除
/// 失败留下的孤儿秘密不属本 module 的回滚语义（known limitation）。
struct CredentialWriteJournal {
  private struct OriginalValue {
    let secret: String?
  }

  let credentials: CredentialStoring
  private var originals: [CredentialReference: OriginalValue] = [:]

  init(credentials: CredentialStoring) {
    self.credentials = credentials
  }

  mutating func save(_ secret: String, for reference: CredentialReference) throws {
    if originals[reference] == nil {
      originals[reference] = OriginalValue(secret: try credentials.secret(for: reference))
    }
    try credentials.save(secret, for: reference)
  }

  /// 尽力删除（幂等）；回滚时恢复改动前的原值或「不存在」。
  mutating func delete(_ reference: CredentialReference) {
    try? deleteOrThrow(reference)
  }

  /// 事务调用方需要知道删除是否成功；保留 `delete` 的既有尽力而为语义
  /// 给目录工作流使用。
  mutating func deleteOrThrow(_ reference: CredentialReference) throws {
    if originals[reference] == nil {
      originals[reference] = OriginalValue(secret: try credentials.secret(for: reference))
    }
    try credentials.delete(reference)
  }

  /// 恢复全部触碰过的引用到改动前的值（尽力），返回逐引用结果。
  func rollback() -> CredentialRollbackOutcome {
    guard !originals.isEmpty else { return .nothingToRestore }
    var restored: Set<CredentialReference> = []
    var failed: Set<CredentialReference> = []
    for (reference, original) in originals {
      let didRestore: Bool
      if let secret = original.secret {
        do {
          try credentials.save(secret, for: reference)
          didRestore = true
        } catch {
          didRestore = false
        }
      } else {
        do {
          try credentials.delete(reference)
          didRestore = true
        } catch {
          didRestore = false
        }
      }
      if didRestore {
        restored.insert(reference)
      } else {
        failed.insert(reference)
      }
    }
    return failed.isEmpty ? .restored(restored) : .partial(restored: restored, failed: failed)
  }
}
