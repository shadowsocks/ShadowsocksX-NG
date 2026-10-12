import Foundation

struct ListenerModeOccupancyContext {
  let listenerMode: ListenerMode
  let proposedListen: RuntimeListenFacts
  let runtimeListen: RuntimeListenFacts?
  let runtimeProcessID: Int32?
}

enum ListenerModeOccupancyGate {
  static func blockedPortIDs(
    results: [SettingsPortID: PortOccupancy],
    context: ListenerModeOccupancyContext
  ) -> [SettingsPortID] {
    SettingsPortID.allCases.filter { id in
      guard let result = results[id], case .occupied = result else { return false }
      return !currentRuntimeOwnsListener(result, for: id, context: context)
    }
  }

  static func unknownPortIDs(in results: [SettingsPortID: PortOccupancy]) -> [SettingsPortID] {
    SettingsPortID.allCases.filter { id in
      guard let result = results[id] else { return false }
      switch result {
      case .unknown:
        return true
      case .occupied(let facts):
        return facts.unverifiedFamilyDetail != nil
      case .free:
        return false
      }
    }
  }

  private static func currentRuntimeOwnsListener(
    _ result: PortOccupancy,
    for id: SettingsPortID,
    context: ListenerModeOccupancyContext
  ) -> Bool {
    let endpoint = SettingsPortAdapter.endpoint(for: id)
    guard
      context.runtimeListen?.port(for: endpoint) == context.proposedListen.port(for: endpoint),
      let processID = context.runtimeProcessID,
      case .occupied(let facts) = result
    else { return false }

    let occupiedProcessIDs = facts.occupiedProcessIDs
    let isVerifiedOwner =
      occupiedProcessIDs == Set([processID])
      && facts.occupiedFamilies.isSubset(of: facts.verifiedFamilies)
    guard !isVerifiedOwner else { return true }

    let isIPv4Mode =
      context.listenerMode == .disabled
      || context.listenerMode == .allIPv4Interfaces
    let isDualStackRuntimeBlockingIPv4 =
      isIPv4Mode
      && facts.occupiedFamilies == [.ipv4]
      && context.runtimeListen?.listenerMode == .allIPv4AndIPv6Interfaces
      && facts.processIDs(for: .ipv4).isEmpty
      && facts.processIDs(for: .ipv6).contains(processID)
      && Set(PortOccupancyAddressFamily.allCases).isSubset(of: facts.verifiedFamilies)
    return isDualStackRuntimeBlockingIPv4
  }

}
