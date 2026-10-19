import Foundation

// 运行状态收敛 module 的配置派生实现；异步计算前捕获事实，恢复后拒绝旧结果。
extension ProxyRuntimeController {
  enum RulePreparationError: Error { case superseded }

  private struct RulePreparationTicket {
    let generation: Int
    let flow: Int
    let modeGeneration: Int
    let settings: ProxyRuntimeSettings
    let target: NodeID?
    let ruleRevision: Int?
  }

  /// Capture mutable facts before leaving the UI actor. A stale task may not
  /// mutate runtime state or write a contract, even when its calculation fails.
  func runtimeDocument(
    _ source: SslocalRuntimeDocument, for mode: ProxyMode
  ) async throws -> SslocalRuntimeDocument {
    runtimePreparationGeneration += 1
    let ticket = RulePreparationTicket(
      generation: runtimePreparationGeneration, flow: flowGeneration,
      modeGeneration: modeChangeGeneration, settings: settings, target: activeTargetID,
      ruleRevision: mode == .rule ? ruleDocuments.revision : nil)
    do {
      let user = mode == .rule ? try ruleDocuments.load() : nil
      let builtIn =
        mode == .rule ? try await runtimeBuiltinRules(ticket.settings.ruleDefaultAction) : []
      let aclURL = runtimeFileStore.aclFileURL
      let result = await Task.detached(priority: .userInitiated) {
        RuleRuntimeCompiler.compile(
          .init(
            source: source, mode: mode, defaultAction: ticket.settings.ruleDefaultAction,
            document: user, builtIn: builtIn, aclURL: aclURL))
      }.value
      guard preparationIsCurrent(ticket) else { throw RulePreparationError.superseded }
      let lan = ticket.settings.listen.lan
      guard lan.isEnabled && lan.authenticationEnabled else { return result.authenticatingLAN(nil) }
      guard let password = lan.password else {
        throw ProxyListeningStoreError.credentialFailure(detail: String(localized: "局域网身份验证密码不可读"))
      }
      let auth = RuntimeListenerAuthentication(
        username: lan.username, password: password,
        directory: runtimeFileStore.fileURL.deletingLastPathComponent().standardizedFileURL.path)
      guard auth.isValid else {
        throw ProxyListeningStoreError.credentialFailure(detail: String(localized: "局域网身份验证凭据无效"))
      }
      return result.authenticatingLAN(auth)
    } catch {
      guard preparationIsCurrent(ticket) else { throw RulePreparationError.superseded }
      throw error
    }
  }

  private func preparationIsCurrent(_ ticket: RulePreparationTicket) -> Bool {
    ticket.generation == runtimePreparationGeneration && ticket.flow == flowGeneration
      && ticket.modeGeneration == modeChangeGeneration
      && ticket.settings.listen == settings.listen
      && ticket.settings.preferredMode == settings.preferredMode
      && ticket.settings.ruleDefaultAction == settings.ruleDefaultAction
      && ticket.settings.agentEnabled == settings.agentEnabled
      && ticket.target == activeTargetID
      && (ticket.ruleRevision == nil || ticket.ruleRevision == ruleDocuments.revision)
  }

  private func runtimeBuiltinRules(_ action: RuleDefaultAction) async throws -> [ProxyRule] {
    switch action {
    case .proxyWhenUnmatched:
      let geolocation = try await ruleSnapshots.load(.geolocationCN)
      let china = try await ruleSnapshots.load(.chinaIPv4)
      return await Task.detached(priority: .userInitiated) {
        BuiltinRuleCatalog.chinaDirectRules(from: [geolocation, china])
      }.value
    case .directWhenUnmatched:
      let snapshot = try await ruleSnapshots.load(.gfwlist)
      return await Task.detached(priority: .userInitiated) {
        BuiltinRuleCatalog.gfwlistRules(from: snapshot)
      }.value
    }
  }

}
