import Foundation

/// Read every document before presenting the catalog so failures never leave partial information.
struct ThirdPartyComponents {
  struct Document: Identifiable {
    let reference: String
    let text: String
    var id: String { reference }
    var name: String { URL(fileURLWithPath: reference).lastPathComponent }
  }

  struct Component: Identifiable {
    let metadata: BundledDependency
    let licenses: [Document]
    let notices: [Document]
    let sharedLicenses: [Document]
    var id: String { metadata.id }
  }

  let components: [Component]

  init(bundleURL: URL = Bundle.main.bundleURL) throws {
    let catalog = try BundledDependencyCatalog(bundleURL: bundleURL)
    components = try catalog.dependencies.sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }.map { dependency in
      var seen: Set<String> = []
      func documents(_ references: [String]) throws -> [Document] {
        try references.filter { seen.insert($0).inserted }.map {
          Document(reference: $0, text: try catalog.text(at: $0))
        }
      }
      let licenses = try documents(dependency.licenses)
      let associated = try documents(dependency.notices)
      func isSharedLicense(_ document: Document) -> Bool {
        document.reference.hasPrefix("third-party-licenses/")
          && document.reference.split(separator: "/").count == 2
      }
      return Component(
        metadata: dependency, licenses: licenses,
        notices: associated.filter { !isSharedLicense($0) },
        sharedLicenses: associated.filter(isSharedLicense))
    }
  }
}
