import Alamofire
import Foundation


let ACLDirPath = NSHomeDirectory() + "/.ShadowsocksX-NG/"


enum ACLAction: String {
    case bypass
    case proxy
}


private func readString(from url: URL) -> String? {
    do {
        let content = try String(contentsOf: url)
        return content
    } catch (let error) {
        let description = String(describing: error)
        NSLog("Reading from \(url) failed: \(description)")
        return nil
    }
}


private func writeString(_ content: String, to url: URL) -> Bool {
    let parent = url.deletingLastPathComponent()

    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: parent.path) {
        do {
            try fileManager.createDirectory(at: parent,
                                            withIntermediateDirectories: true)
        } catch (let error) {
            let description = String(describing: error)
            NSLog("Creating directory \(parent) failed: \(description)")
            return false
        }
    }

    do {
        try content.write(to: url, atomically: true, encoding: .utf8)
        return true
    } catch (let error) {
        let description = String(describing: error)
        NSLog("Writing to \(url) failed: \(description)")
        return false
    }
}


enum ACLRule: String {
    case bypassLANChina
    case proxyGFWList
    case custom

    func load() -> String {
        // One can override the default rules by writing custom rules
        // to a specific file
        let overridePath = ACLDirPath + filename
        let overrideUrl = URL(fileURLWithPath: overridePath)
        if let content = readString(from: overrideUrl) {
            return content
        }
        // Two force unwraps because it is a builtin file
        let url = Bundle.main.url(forResource: resourceName, withExtension: "acl")!
        return readString(from: url)!
    }

    func save(content: String) -> Bool {
        let path = ACLDirPath + filename
        let url = URL(fileURLWithPath: path)
        return writeString(content, to: url)
    }

    func exportTo(_ url: URL) -> Bool {
        let content = load()
        return writeString(content, to: url)
    }

    func importFrom(_ url: URL) -> Bool {
        guard let source = readString(from: url) else {
            return false
        }
        let parsed = ACLRule.parse(content: source)
        let content = ACLRule.compose(proxyList: parsed.proxyList,
                                      bypassList: parsed.bypassList)
        return save(content: content)
    }

    static func compose(proxyList: [String],
                        bypassList: [String],
                        defaultAction: ACLAction? = nil) -> String {
        var sections = [String]()

        switch defaultAction {
        case .some(.bypass):
            sections.append("[bypass_all]")

        case .some(.proxy):
            sections.append("[proxy_list]")

        default:
            break
        }

        sections.append(contentsOf: [
            "[proxy_list]",
            proxyList.joined(separator: "\n"),
            "[bypass_list]",
            bypassList.joined(separator: "\n"),
        ])

        return sections.joined(separator: "\n")
    }

    static func parse(content: String) -> (proxyList: [String], bypassList: [String]) {
        let lines = content.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var proxyList = [String]()
        var bypassList = [String]()
        var currentAction: ACLAction?
        for line in lines {
            if line.isEmpty {
                continue
            }

            switch line {
            case "[bypass_list]":
                currentAction = .bypass

            case "[proxy_list]":
                currentAction = .proxy

            default:
                guard let action = currentAction else {
                    continue
                }
                switch action {
                case .bypass:
                    bypassList.append(line)

                case .proxy:
                    proxyList.append(line)
                }
            }
        }
        return (proxyList, bypassList)
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


// TODO: IP / CIDR / Regexp
@objc(ACLEntry)
class ACLEntry: NSObject {
    dynamic var stringValue: String

    override init() {
        self.stringValue = ""
    }

    init(stringValue value: String) {
        self.stringValue = value
    }
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
        let url = URL(fileURLWithPath: filePath)
        let content = generateContent()

        guard writeString(content, to: url) else {
            return nil
        }
        return filePath
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


private func ACLEntryFrom(rule: String) -> (action: ACLAction, entry: ACLEntry)? {
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
    return (action, ACLEntry(stringValue: regexp))
}


private func ABPFilterToACL(filter: String) -> String {
    let rules = filter.components(separatedBy: .newlines)

    var entries = rules.flatMap(ACLEntryFrom(rule:))
    let p = entries.partition { $0.action == .bypass }
    let regexps = entries.map { $0.entry.stringValue }
    let proxyList = regexps.prefix(upTo: p)
    let bypassList = regexps.suffix(from: p)

    return ACLRule.compose(proxyList: Array(proxyList),
                           bypassList: Array(bypassList),
                           defaultAction: .proxy)
}


private func GFWListToACL(gfwlist: String) -> String? {
    guard let decoded = Data(base64Encoded: gfwlist, options: .ignoreUnknownCharacters) else {
        return nil
    }
    guard let gfwlistFilter = String(data: decoded, encoding: .utf8) else {
        return nil
    }

    return ABPFilterToACL(filter: gfwlistFilter)
}


private func SendNotification(message: String) {
    let notification = NSUserNotification()
    notification.title = message
    NSUserNotificationCenter.default.deliver(notification)
}


func UpdateGFWListACL() {
    guard let url = UserDefaults.standard.string(forKey: "GFWListURL") else {
        SendNotification(message: "Invalid GFW List URL.".localized)
        return
    }

    do {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: ACLDirPath) {
            try fileManager.createDirectory(atPath: ACLDirPath, withIntermediateDirectories: true)
        }
    } catch {
        SendNotification(message: "ACL Directory cannot be created.".localized)
        return
    }

    Alamofire.request(url).responseString { response in
        switch response.result {
        case .success(let gfwlist):
            let message: String

            if let aclContent = GFWListToACL(gfwlist: gfwlist) {
                if ACLRule.proxyGFWList.save(content: aclContent) {
                    message = "ACL has been updated by lastest GFW List.".localized

                    // This will reload ACL if the generated ACL is changed
                    SyncSSLocal()
                } else {
                    message = "Failed to write GFW List ACL".localized
                }
            } else {
                message = "Failed parse GFW List into ACL.".localized
            }

            SendNotification(message: message)

        case .failure(let error):
            let description = String(reflecting: error)
            NSLog("Error fetching GFWList: \(description)")
            
            SendNotification(message: "Failed to download latest GFW List.".localized)
        }
    }
}
