import Foundation


let ACLDirPath = NSHomeDirectory() + "/.ShadowsocksX-NG/"
let ACLBypassLANChinaFilePath = ACLDirPath + "bypass-lan-china.acl"
let ACLGFWListFilePath = ACLDirPath + "gfwlist.acl"


struct ACLEntry {
    let bypass: Bool
    let regexp: String
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

    return ACLEntry(bypass: exceptionRule, regexp: regexp)
}


private func ABPFilterToACL(filter: String) -> String {
    let rules = filter.components(separatedBy: .newlines)

    var entries = rules.flatMap(ACLEntryFrom(rule:))
    let p = entries.partition { $0.bypass }
    let regexps = entries.map { $0.regexp }
    let proxyList = regexps.prefix(upTo: p).joined(separator: "\n")
    let bypassList = regexps.suffix(from: p).joined(separator: "\n")

    // Swift 4: Change this to a multiline string literal for better readability
    return "[bypass_all]\n\n[proxy_list]\n\(proxyList)\n\n[bypass_list]\n\(bypassList)\n"
}


func Generate(ACLFile output: String, FromGFWList gfwlist: String, AndABPFile abp: String) -> Bool {
    guard let base64Filter = try? String(contentsOfFile: gfwlist) else {
        return false
    }
    guard let decoded = Data(base64Encoded: base64Filter, options: .ignoreUnknownCharacters),
        let gfwlistFilter = String(data: decoded, encoding: .utf8) else {
        return false
    }
    guard let abpFilter = try? String(contentsOfFile: abp) else {
        return false
    }

    let filter = "\(abpFilter)\n\(gfwlistFilter)"
    let acl = ABPFilterToACL(filter: filter)

    guard let aclData = acl.data(using: .utf8) else {
        return false
    }

    return (try? aclData.write(to: URL(fileURLWithPath: output))) != nil
}


func GenerateGFWListACL() {
    EnsureGFWList()
    EnsureUserRule()

    if !Generate(ACLFile: ACLGFWListFilePath,
                 FromGFWList: GFWListFilePath,
                 AndABPFile: PACUserRuleFilePath) {
        NSLog("Generate GFWList ACL failed")
    }
}


func EnsureBypassLANChinaACL() {
    let dst = ACLBypassLANChinaFilePath
    let fileMgr = FileManager.default

    if fileMgr.fileExists(atPath: dst) {
        return
    }

    let src = Bundle.main.path(forResource: "bypass-lan-china", ofType: "acl")!
    try! fileMgr.copyItem(atPath: src, toPath: dst)
}


func EnsureGFWListACL() {
    let dst = ACLGFWListFilePath
    let fileMgr = FileManager.default

    if fileMgr.fileExists(atPath: dst) {
        return
    }

    GenerateGFWListACL()
}
