/// 状态机产出的效应由运行时接线消费。
enum ActivationEffect: Equatable, Sendable {
  /// 原子更新运行时（首次激活、重激活或子树编辑重展开成功）。
  case deployed(RuntimeConfiguration)
  /// 清除活动目标并停止代理（点名原因，无静默回退）。
  case clearedAndStopped(ActivationFailure)
}

/// 派生运行时文档的监听与行为设置；聚合状态机接口的传参。
struct RuntimeDocumentOptions: Equatable, Sendable {
  var listen: SslocalListenSettings
}

extension ProxySettings {
  /// 激活派生所用的监听配置。
  var runtimeDocumentOptions: RuntimeDocumentOptions {
    RuntimeDocumentOptions(listen: listen)
  }
}

/// 激活状态机持久化活动目标（服务器或分组的节点身份）。
/// 激活是单缝原子操作——成功替换目标并产出派生文档，失败点名原因且状态不动；
/// 目录提交后立即重展开，目标失效即清除并发出停止意图。运行时文件写入与
/// 运行时接线消费本层产出，以控制进程启停。
struct ActivationStateMachine: Equatable, Sendable {
  /// 当前活动目标；`nil` 即无目标（代理不应运行）。
  private(set) var activeTargetID: NodeID?

  /// 从持久化恢复（`ActivationStateFileStore`）；恢复后的有效性由下一次
  /// `catalogDidCommit` 重校验同步（「GUI 下次启动重新校验同步」）。
  init(activeTargetID: NodeID? = nil) {
    self.activeTargetID = activeTargetID
  }

  /// 显式激活。成功：目标替换、返回派生文档；失败：抛点名原因，状态完全不动
  /// （保留原目标与运行状态，无静默回退）。
  mutating func activate(
    _ target: NodeID,
    in catalog: ConfigurationCatalog,
    credentials: CredentialStoring,
    plugins: PluginExecutableResolving,
    options: RuntimeDocumentOptions
  ) throws -> RuntimeConfiguration {
    let outcome = derive(
      target: target, in: catalog, credentials: credentials, plugins: plugins, options: options)
    switch outcome {
    case .success(let configuration):
      activeTargetID = target
      return configuration
    case .failure(let failure):
      throw failure
    }
  }

  /// 目录已提交变更后的立即重展开。返回 `nil` 表示无事可做（无活动目标）；
  /// 有效非空 → `.deployed`（原子更新）；目标被删除/变空/无有效叶子 →
  /// 清除目标并返回 `.clearedAndStopped`（点名原因）。任何目录提交（含与活动
  /// 目标无关的编辑）都整体重校验重展开：产出对相同输入幂等；运行时接线决定是否
  /// 跳过相同内容的运行时写入。
  mutating func catalogDidCommit(
    _ catalog: ConfigurationCatalog,
    credentials: CredentialStoring,
    plugins: PluginExecutableResolving,
    options: RuntimeDocumentOptions
  ) -> ActivationEffect? {
    guard let target = activeTargetID else { return nil }
    let outcome = derive(
      target: target, in: catalog, credentials: credentials, plugins: plugins, options: options)
    switch outcome {
    case .success(let configuration):
      return .deployed(configuration)
    case .failure(let failure):
      activeTargetID = nil
      return .clearedAndStopped(failure)
    }
  }

  // MARK: - 展开、校验与派生

  /// 单缝派生：目标存在 → 显式子序深度优先展开全部叶子 → 逐叶进行 app
  /// 可知的激活预检 → 解析凭据。单个服务器目标遇到阻塞原因时整体拒绝；
  /// 分组目标则跳过已知无效叶子，至少保留一台服务器才产出运行时文档。
  private func derive(
    target: NodeID,
    in catalog: ConfigurationCatalog,
    credentials: CredentialStoring,
    plugins: PluginExecutableResolving,
    options: RuntimeDocumentOptions
  ) -> Result<RuntimeConfiguration, ActivationFailure> {
    guard catalog.contains(target) else { return .failure(.targetNotFound(target)) }
    let plugins = plugins.catalogSnapshot()
    let isGroup = isGroupTarget(target, in: catalog)
    var leaves: [NodeID] = []
    if isGroup {
      collectServerLeaves(of: target, in: catalog, into: &leaves)
    } else {
      leaves = [target]
    }
    guard !leaves.isEmpty else { return .failure(.targetExpandsToNothing(target)) }

    var servers: [SslocalServerDocument] = []
    var skippedServers: [SkippedServer] = []
    for leafID in leaves {
      switch deriveLeaf(leafID, in: catalog, credentials: credentials, plugins: plugins) {
      case .server(let server):
        servers.append(server)
      case .skippedCandidate(let skipped):
        // 分组目标跳过已知无效叶子；单服务器目标整体拒绝且状态不动。
        if isGroup {
          skippedServers.append(skipped)
        } else {
          return .failure(.invalidLeaf(node: skipped.id, reason: skipped.reason))
        }
      case .failed(let failure):
        return .failure(failure)
      }
    }
    guard !servers.isEmpty else { return .failure(.targetExpandsToNothing(target)) }
    return .success(
      RuntimeConfiguration(
        targetID: target,
        document: SslocalRuntimeDocument(
          servers: servers,
          listen: options.listen),
        skippedServers: skippedServers))
  }

  private func isGroupTarget(_ target: NodeID, in catalog: ConfigurationCatalog) -> Bool {
    guard let entry = catalog.entry(for: target) else { return false }
    if case .group = entry.kind { return true }
    return false
  }

  /// 单叶派生结果。`.skippedCandidate` 携带点名原因，分组语义下可跳过，
  /// 单服务器目标由调用方转成整体拒绝。
  private enum LeafDerival {
    case server(SslocalServerDocument)
    case skippedCandidate(SkippedServer)
    case failed(ActivationFailure)
  }

  private func deriveLeaf(
    _ leafID: NodeID,
    in catalog: ConfigurationCatalog,
    credentials: CredentialStoring,
    plugins: PluginExecutableResolving
  ) -> LeafDerival {
    guard let entry = catalog.entry(for: leafID), case .server(let fields) = entry.kind else {
      preconditionFailure("展开结果只含服务器叶子")
    }
    let validation = ServerValidation.evaluate(fields, credentials: credentials, plugins: plugins)
    if let issue = validation.issues.first {
      return .skippedCandidate(SkippedServer(id: leafID, reason: issue))
    }
    switch derivedServer(leafID, in: catalog, credentials: credentials, plugins: plugins) {
    case .success(let server):
      return .server(server)
    case .failure(let failure):
      if case .invalidLeaf(let node, let reason) = failure {
        return .skippedCandidate(SkippedServer(id: node, reason: reason))
      }
      return .failed(failure)
    }
  }

  /// 按显式子序深度优先收集全部服务器叶子；有效性在派生阶段统一预检。
  /// 目录结构不变量（子引用必存在、目标必为分组）由构造校验保证，失约即程序错误。
  private func collectServerLeaves(
    of groupID: NodeID,
    in catalog: ConfigurationCatalog,
    into leaves: inout [NodeID]
  ) {
    guard case .group(let fields) = catalog.entry(for: groupID)?.kind else {
      preconditionFailure("展开目标已先行校验为分组")
    }
    for child in fields.children {
      guard let entry = catalog.entry(for: child) else {
        preconditionFailure("目录结构不变量：子引用必存在")
      }
      switch entry.kind {
      case .server:
        leaves.append(child)
      case .group:
        collectServerLeaves(of: child, in: catalog, into: &leaves)
      }
    }
  }

  /// 校验单个有效候选叶子并解析为上游条目；凭据在派生时从凭据存储解析。
  private func derivedServer(
    _ leafID: NodeID,
    in catalog: ConfigurationCatalog,
    credentials: CredentialStoring,
    plugins: PluginExecutableResolving
  ) -> Result<SslocalServerDocument, ActivationFailure> {
    guard let entry = catalog.entry(for: leafID), case .server(let fields) = entry.kind else {
      preconditionFailure("展开结果只含服务器叶子")
    }
    let password: String
    switch resolveCredential(fields.passwordRef, of: leafID, credentials: credentials) {
    case .success(let resolved):
      password = resolved
    case .failure(let failure):
      return .failure(failure)
    }
    var pluginPath: String?
    var pluginOpts: String?
    var pluginArgs: [String]?
    var pluginMode: PluginTransportMode?
    if let program = fields.pluginProgram {
      guard let resolved = plugins.resolve(program: program) else {
        return .failure(.invalidLeaf(node: leafID, reason: .pluginNotProvided(program: program)))
      }
      pluginMode = resolved.mode == .tcpOnly ? nil : resolved.mode
      pluginPath = resolved.path
      pluginArgs = resolved.arguments.isEmpty ? nil : resolved.arguments
      if let optionsRef = fields.pluginOptionsRef {
        switch resolveCredential(optionsRef, of: leafID, credentials: credentials) {
        case .success(let resolved):
          pluginOpts = resolved
        case .failure(let failure):
          return .failure(failure)
        }
      }
    }
    return .success(
      SslocalServerDocument(
        id: leafID.rawValue,
        server: fields.address.trimmingCharacters(in: .whitespacesAndNewlines),
        serverPort: fields.port,
        password: password,
        method: fields.encryptionMethod.trimmingCharacters(in: .whitespacesAndNewlines),
        plugin: pluginPath,
        pluginOpts: pluginOpts, pluginArgs: pluginArgs, pluginMode: pluginMode))
  }

  /// 凭据解析：无条目与读取失败分别点名（「凭据不可解析 → 停止并清理」）。
  private func resolveCredential(
    _ reference: CredentialReference,
    of leafID: NodeID,
    credentials: CredentialStoring
  ) -> Result<String, ActivationFailure> {
    do {
      guard let secret = try credentials.secret(for: reference), !secret.isEmpty else {
        return .failure(.invalidLeaf(node: leafID, reason: .credentialUnresolved(reference)))
      }
      return .success(secret)
    } catch {
      return .failure(.invalidLeaf(node: leafID, reason: .credentialReadFailed(reference)))
    }
  }
}
