import Foundation

extension CatalogTreeNode {
  var connectivityServerIDs: [NodeID] {
    isGroup ? childNodes.flatMap(\.connectivityServerIDs) : [id]
  }
}

extension CatalogWorkflow {
  /// Hash connection facts only; display-name and directory edits preserve observations.
  func connectivityRevision(for id: NodeID) -> String {
    guard let entry = dependencies.coordinator.committedCatalog.entry(for: id),
      case .server(var fields) = entry.kind
    else { return "missing" }
    fields.remark = ""
    let plugin = fields.pluginProgram.flatMap {
      dependencies.plugins.catalogSnapshot().entry(for: $0)
    }
    let secrets = [fields.passwordRef, fields.pluginOptionsRef].compactMap { $0 }.map {
      (try? dependencies.credentials.secret(for: $0)) ?? "unreadable"
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let facts =
      [
        String(data: (try? encoder.encode(fields)) ?? Data(), encoding: .utf8) ?? "",
        String(describing: plugin),
      ] + secrets
    return ProxyACLDocument.digest((try? JSONEncoder().encode(facts)) ?? Data())
  }

  /// Captures all descendants in catalog order, independently of UI collapse or sort.
  func connectivityTargets(source: NodeSource?) -> [NodeID] {
    let nodes = source == nil ? favorites : tree.roots.filter { $0.source == source }
    var seen = Set<NodeID>()
    return nodes.flatMap(\.connectivityServerIDs).filter { seen.insert($0).inserted }
  }

  /// This local state machine derives a single leaf without publishing activation.
  func connectivityConfiguration(for id: NodeID) throws -> SslocalServerDocument {
    let catalog = dependencies.coordinator.committedCatalog
    guard case .server? = catalog.entry(for: id)?.kind else { throw ServerFormLoadError.notFound }
    var derivation = ActivationStateMachine()
    if case .server(let fields)? = catalog.entry(for: id)?.kind,
      !EncryptionMethodCatalog.isSupported(fields.encryptionMethod)
    {
      throw ServerConnectivity.ConfigurationFailure.unsupported
    }
    let config = try derivation.activate(
      id, in: catalog, credentials: dependencies.credentials,
      plugins: dependencies.plugins,
      options: RuntimeDocumentOptions(listen: SslocalListenSettings()))
    guard let server = config.document.servers.first else { throw ServerFormLoadError.notFound }
    return server
  }
}
