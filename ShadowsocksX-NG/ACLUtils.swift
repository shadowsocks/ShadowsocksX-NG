import Foundation


let ACLDirPath = NSHomeDirectory() + "/.ShadowsocksX-NG/"


enum ACLAction: String {
    case bypass
    case proxy
}


enum ACLRule: String {
    case bypassLANChina
    case proxyGFWList
    case custom

    func load() -> String {
        // One can override the default rules by writing custom rules
        // to a specific file
        let overridePath = ACLDirPath + filename
        if let content = try? String(contentsOfFile: overridePath) {
            return content
        }
        // Two force unwraps because it is a builtin file
        let path = Bundle.main.path(forResource: resourceName, ofType: "acl")!
        return try! String(contentsOfFile: path)
    }

    private var resourceName: String {
        switch self {
        case .bypassLANChina:
            return "bypass-lan-china"

        case .proxyGFWList:
            return "gfwlist"

        case .custom:
            return "custom"
        }
    }

    private var filename: String {
        return "\(resourceName).acl"
    }
}


struct ACLEntry {
    let action: ACLAction
    let regexp: String
}


class ACLManager {

    static let instance = ACLManager(userDefaults: UserDefaults.standard)

    private let userDefaults: UserDefaults
    private let filePath: String

    // Chosen when the request does not match any other rules
    var defaultAction: ACLAction {
        get {
            guard let stored = userDefaults.string(forKey: "ACL.Default") else {
                return .proxy
            }
            guard let action = ACLAction(rawValue: stored) else {
                return .proxy
            }
            return action
        }
        set {
            let stored = newValue.rawValue
            userDefaults.set(stored, forKey: "ACL.Default")
        }
    }

    // Which builtin rules to include in the generated ACL file
    var enabledRules: Set<ACLRule> {
        get {
            // Custom rules are always active
            // You can edit it by editing ~/.ShadowsocksX-NG/custom.acl
            let alwaysActiveRules: Set<ACLRule> = [.custom]

            guard let raw = userDefaults.array(forKey: "ACL.Rules") else {
                return alwaysActiveRules
            }
            guard let stored = raw as? [String] else {
                return alwaysActiveRules
            }
            let rules = stored.flatMap { ACLRule(rawValue: $0) }
            return Set(rules).union(alwaysActiveRules)
        }
        set {
            let stored = newValue.map { $0.rawValue }
            userDefaults.set(stored, forKey: "ACL.Rules")
        }
    }

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        self.filePath = ACLDirPath + ".generated.acl"
    }

    func hash() -> String {
        return getFileSHA1Sum(filePath)
    }

    func generate() -> String? {
        let content = generateContent()

        do {
            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            return filePath
        } catch {
            return nil
        }
    }

    private func generateContent() -> String {
        var contents = [String]()

        switch defaultAction {
        case .bypass:
            contents.append("[bypass_all]")

        case .proxy:
            contents.append("[proxy_all]")
        }

        for rule in enabledRules {
            contents.append(rule.load())
        }

        return contents.joined(separator: "\n")
    }
}


private func ACLEntryFrom(rule: String) -> ACLEntry? {
    // Skip empty lines and comment
    let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return nil
    }
    if trimmed.hasPrefix("!") || trimmed.hasPrefix("[") {
        return nil
    }

    var body = trimmed

    let exceptionRule = trimmed.hasPrefix("@@")
    if exceptionRule {
        let ruleIndex = body.index(body.startIndex, offsetBy: 2)
        body = body.substring(from: ruleIndex)
    }

    // Strip options, since they have nothing to do with the ACL
    let optionsPattern = "\\$(~?[\\w\\-]+(?:=[^,\\s]+)?(?:,~?[\\w\\-]+(?:=[^,\\s]+)?)*)$"
    if let range = body.range(of: optionsPattern, options: .regularExpression) {
        body = body.substring(to: range.lowerBound)
    }

    let regexp: String

    if body.characters.count > 2 && body.hasPrefix("/") && body.hasSuffix("/") {
        let start = body.characters.index(after: body.characters.startIndex)
        let end = body.characters.index(before: body.characters.endIndex)
        regexp = body.substring(with: start..<end)
    } else {
        // remove http:// and https:// from rules
        body = body.replacingOccurrences(of: "(^|\\|)https?://", with: "", options: .regularExpression)

        // A huge mess from the ADBlock Plus Javascript implementation
        regexp = body.replacingOccurrences(of: "\\*+", with: "*", options: .regularExpression)
            .replacingOccurrences(of: "\\^\\|$", with: "^", options: .regularExpression)
            .replacingOccurrences(of: "\\W", with: "\\\\$0", options: .regularExpression)
            .replacingOccurrences(of: "\\\\\\*", with: ".*", options: .regularExpression)
            .replacingOccurrences(of: "\\\\\\^", with: "(?:[\\\\x00-\\\\x24\\\\x26-\\\\x2C\\\\x2F\\\\x3A-\\\\x40\\\\x5B-\\\\x5E\\\\x60\\\\x7B-\\\\x7F]|$)", options: .regularExpression)
            // This one is modified, as the original implementation matches schema too
            .replacingOccurrences(of: "^\\\\\\|\\\\\\|", with: "(^|\\.)", options: .regularExpression)
            .replacingOccurrences(of: "^\\\\\\|", with: "^", options: .regularExpression)
            .replacingOccurrences(of: "\\\\\\|$", with: "$", options: .regularExpression)
            .replacingOccurrences(of: "^(\\.\\*)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(\\.\\*)$", with: "", options: .regularExpression)
    }

    // Due to a bug in shadowsocks-libev, the regular expression in ACL
    // have a 256 character limit
    if regexp.characters.count > 255 {
        return nil
    }

    let action: ACLAction = exceptionRule ? .bypass : .proxy
    return ACLEntry(action: action, regexp: regexp)
}


private func ABPFilterToACL(filter: String) -> String {
    let rules = filter.components(separatedBy: .newlines)

    var entries = rules.flatMap(ACLEntryFrom(rule:))
    let p = entries.partition { $0.action == .bypass }
    let regexps = entries.map { $0.regexp }
    let proxyList = regexps.prefix(upTo: p).joined(separator: "\n")
    let bypassList = regexps.suffix(from: p).joined(separator: "\n")

    // Swift 4: Change this to a multiline string literal for better readability
    return "[bypass_all]\n\n[proxy_list]\n\(proxyList)\n\n[bypass_list]\n\(bypassList)\n"
}


private func Generate(ACLFile output: String, FromGFWList gfwlist: String) -> Bool {
    guard let base64Filter = try? String(contentsOfFile: gfwlist) else {
        return false
    }
    guard let decoded = Data(base64Encoded: base64Filter, options: .ignoreUnknownCharacters),
        let gfwlistFilter = String(data: decoded, encoding: .utf8) else {
        return false
    }

    let acl = ABPFilterToACL(filter: gfwlistFilter)

    guard let aclData = acl.data(using: .utf8) else {
        return false
    }

    return (try? aclData.write(to: URL(fileURLWithPath: output))) != nil
}
