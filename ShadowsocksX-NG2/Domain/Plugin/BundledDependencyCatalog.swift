import Foundation

/// Offline facts for shipped direct dependencies; executable selection does not depend on this data.
struct BundledDependency: Codable, Equatable, Sendable {
  let id: String
  let name: String
  let projectURL: String
  let sourceURL: String
  let distributionURL: String
  let version: String
  let licenses: [String]
  let notices: [String]
}

struct BundledDependencyCatalog: Sendable {
  let dependencies: [BundledDependency]
  private let resourcesURL: URL

  private struct Document: Decodable {
    let schemaVersion: Int
    let dependencies: [BundledDependency]
  }

  enum CatalogError: Error {
    case invalidMetadata
    case invalidTextReference(String)
  }

  init(bundleURL: URL = Bundle.main.bundleURL) throws {
    resourcesURL = bundleURL.appendingPathComponent("Contents/Resources/ThirdParty")
    let document = try JSONDecoder().decode(
      Document.self, from: Data(contentsOf: resourcesURL.appendingPathComponent("catalog.json")))
    guard document.schemaVersion == 1, !document.dependencies.isEmpty,
      Set(document.dependencies.map(\.id)).count == document.dependencies.count
    else { throw CatalogError.invalidMetadata }
    dependencies = document.dependencies
    for dependency in dependencies {
      guard !dependency.id.isEmpty, !dependency.name.isEmpty, !dependency.version.isEmpty,
        !dependency.licenses.isEmpty,
        [dependency.projectURL, dependency.sourceURL, dependency.distributionURL].allSatisfy({
          guard let url = URL(string: $0) else { return false }
          return url.scheme == "https" && url.host != nil
        })
      else { throw CatalogError.invalidMetadata }
      for reference in dependency.licenses + dependency.notices {
        _ = try text(at: reference)
      }
    }
  }

  func text(at reference: String) throws -> String {
    let root = resourcesURL.resolvingSymlinksInPath().standardizedFileURL
    let url = root.appendingPathComponent(reference).resolvingSymlinksInPath().standardizedFileURL
    guard !reference.isEmpty, url.path.hasPrefix(root.path + "/") else {
      throw CatalogError.invalidTextReference(reference)
    }
    let text = try String(contentsOf: url, encoding: .utf8)
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CatalogError.invalidTextReference(reference)
    }
    return text
  }
}
