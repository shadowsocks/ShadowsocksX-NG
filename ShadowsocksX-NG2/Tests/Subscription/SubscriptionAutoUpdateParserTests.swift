import Foundation
import Testing

@testable import ShadowsocksX_NG2

struct SubscriptionAutoUpdateParserTests {
  @Test(arguments: SubscriptionUpdateMode.allCases, [false, true])
  func acceptsOnlyCompletePolicies(mode: SubscriptionUpdateMode, allowsOverride: Bool) throws {
    let snapshot = try parse(
      #"{"schema_version":1,"auto_update":{"mode":"\#(mode.rawValue)","allow_user_override":\#(allowsOverride)}}"#
    )
    #expect(
      snapshot.autoUpdatePolicy == .valid(.init(mode: mode, allowUserOverride: allowsOverride)))
  }

  @Test(arguments: [
    #"{}"#, #"null"#, #"false"#, #"[]"#,
    #"{"mode":"daily"}"#, #"{"allow_user_override":true}"#,
    #"{"mode":"hourly","allow_user_override":true}"#,
    #"{"mode":1,"allow_user_override":true}"#,
    #"{"mode":"daily","allow_user_override":1}"#,
    #"{"mode":"daily","allow_user_override":"true"}"#,
  ])
  func malformedPoliciesDoNotRejectServers(policy: String) throws {
    let snapshot = try parse(#"{"schema_version":1,"auto_update":\#(policy)}"#)
    #expect(snapshot.autoUpdatePolicy == .invalid)
    #expect(snapshot.root.children.count == 1)
  }

  @Test func invalidTreeAndPolicyAreIndependent() throws {
    let validPolicy = try parse(
      #"{"schema_version":1,"groups":false,"auto_update":{"mode":"weekly","allow_user_override":false}}"#
    )
    #expect(validPolicy.autoUpdatePolicy == .valid(.init(mode: .weekly, allowUserOverride: false)))
    #expect(validPolicy.root.children.count == 1)
    let validTree = try parse(
      #"""
      {"schema_version":1,
      "root_group_id":"root",
      "groups":[{"id":"root",
      "name":"Provider tree",
      "children":[]}],
      "auto_update":{}}
      """#
    )
    #expect(validTree.root.name == "Provider tree")
    #expect(validTree.autoUpdatePolicy == .invalid)
  }

  @Test func unsupportedVersionDoesNotAdoptPolicyAndMissingPolicyWithdraws() throws {
    #expect(
      try parse(#"{"schema_version":2,"auto_update":{"mode":"daily","allow_user_override":false}}"#)
        .autoUpdatePolicy == .invalid)
    #expect(try parse(#"{"schema_version":1}"#).autoUpdatePolicy == .absent)
    let absent = try SubscriptionDocumentParser.parse(
      Data(#"{"version":1,"servers":[]}"#.utf8), subscriptionID: .fresh())
    #expect(absent.autoUpdatePolicy == .absent)
  }

  private func parse(_ namespace: String) throws -> SubscriptionSnapshot {
    let data = Data(
      """
      {"version":1,"servers":[{"server":"example.com","server_port":8388,
      "method":"aes-256-gcm","password":"password"}],"x_shadowsocksx_ng":\(namespace)}
      """.utf8)
    return try SubscriptionDocumentParser.parse(data, subscriptionID: .fresh())
  }
}
