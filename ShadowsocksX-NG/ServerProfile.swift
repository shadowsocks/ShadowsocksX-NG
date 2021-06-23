//
//  ServerProfile.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/6.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Cocoa


class ServerProfile: NSObject, NSCopying {
    
    @objc var uuid: String

    @objc var serverHost: String = ""
    @objc var serverPort: uint16 = 8379
    @objc var method:String = "aes-128-gcm"
    @objc var password:String = ""
    @objc var remark:String = ""
    
    // SIP003 Plugin
    @objc var plugin: String = ""  // empty string disables plugin
    @objc var pluginOptions: String = ""
    
    override init() {
        uuid = UUID().uuidString
    }

    init(uuid: String) {
        self.uuid = uuid
    }

    convenience init?(url: URL) {
        self.init()

        func padBase64(string: String) -> String {
            var length = string.utf8.count
            if length % 4 == 0 {
                return string
            } else {
                length = 4 - length % 4 + length
                return string.padding(toLength: length, withPad: "=", startingAt: 0)
            }
        }

        func decodeUrl(url: URL) -> (String?,String?) {
            let urlStr = url.absoluteString
            let base64Begin = urlStr.index(urlStr.startIndex, offsetBy: 5)
            let base64End = urlStr.firstIndex(of: "#")
            let encodedStr = String(urlStr[base64Begin..<(base64End ?? urlStr.endIndex)])
            guard let data = Data(base64Encoded: padBase64(string: encodedStr)) else {
                // Not legacy format URI
                return (url.absoluteString, nil)
            }
            guard let decoded = String(data: data, encoding: String.Encoding.utf8) else {
                return (nil, nil)
            }
            var s = decoded.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
            
            // May be legacy format URI
            // Note that the legacy URI doesn't follow RFC3986. It means the password here
            // should be plain text, not percent-encoded.
            // Ref: https://shadowsocks.org/en/config/quick-guide.html
            let parser = try? NSRegularExpression(
                pattern: "(.+):(.+)@(.+)", options: .init())
            if let match = parser?.firstMatch(in:s, options: [], range: NSRange(location: 0, length: s.utf16.count)) {
                // Convert legacy format to SIP002 format
                let r1 = Range(match.range(at: 1), in: s)!
                let r2 = Range(match.range(at: 2), in: s)!
                let r3 = Range(match.range(at: 3), in: s)!
                let user = String(s[r1])
                let password = String(s[r2])
                let hostAndPort = String(s[r3])
                
                let rawUserInfo = "\(user):\(password)".data(using: .utf8)!
                let userInfo = rawUserInfo.base64EncodedString()
                
                s = "ss://\(userInfo)@\(hostAndPort)"
            }
            
            if let index = base64End {
                let i = urlStr.index(index, offsetBy: 1)
                let fragment = String(urlStr[i...])
                return (s, fragment.removingPercentEncoding)
            }
            return (s, nil)
        }
        func decodeLegacyFormat(url: String) -> (URL?,String?) {
            return (nil, nil)
        }
        
        let (_decodedUrl, _tag) = decodeUrl(url: url)
        guard let decodedUrl = _decodedUrl else {
            return nil
        }
        guard let parsedUrl = URLComponents(string: decodedUrl) else {
            return nil
        }
        guard let host = parsedUrl.host, let port = parsedUrl.port,
            let user = parsedUrl.user else {
            return nil
        }

        self.serverHost = host
        self.serverPort = UInt16(port)

        // This can be overriden by the fragment part of SIP002 URL
        remark = parsedUrl.queryItems?
            .filter({ $0.name == "Remark" }).first?.value ?? ""
        
        if let tag = _tag {
            remark = tag
        }

        // SIP002 URL have no password section
        guard let data = Data(base64Encoded: padBase64(string: user)),
            let userInfo = String(data: data, encoding: .utf8) else {
            return nil
        }

        let parts = userInfo.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count != 2 {
            return nil
        }
        self.method = String(parts[0]).lowercased()
        self.password = String(parts[1])

        // SIP002 defines where to put the profile name
        if let profileName = parsedUrl.fragment {
            self.remark = profileName
        }

        if let pluginStr = parsedUrl.queryItems?
            .filter({ $0.name == "plugin" }).first?.value {
            let parts = pluginStr.split(separator: ";", maxSplits: 1)
            if parts.count == 2 {
                plugin = String(parts[0])
                pluginOptions = String(parts[1])
            } else if parts.count == 1 {
                plugin = String(parts[0])
            }
        }
    }
    
    public func copy(with zone: NSZone? = nil) -> Any {
        let copy = ServerProfile()
        copy.serverHost = self.serverHost
        copy.serverPort = self.serverPort
        copy.method = self.method
        copy.password = self.password
        copy.remark = self.remark
        
        copy.plugin = self.plugin
        copy.pluginOptions = self.pluginOptions
        return copy;
    }
    
    static func fromDictionary(_ data:[String:Any?]) -> ServerProfile {
        let cp = {
            (profile: ServerProfile) in
            profile.serverHost = data["ServerHost"] as! String
            profile.serverPort = (data["ServerPort"] as! NSNumber).uint16Value
            profile.method = data["Method"] as! String
            profile.password = data["Password"] as! String
            if let remark = data["Remark"] {
                profile.remark = remark as! String
            }
            if let plugin = data["Plugin"] as? String {
                profile.plugin = plugin
            }
            if let pluginOptions = data["PluginOptions"] as? String {
                profile.pluginOptions = pluginOptions
            }
        }

        if let id = data["Id"] as? String {
            let profile = ServerProfile(uuid: id)
            cp(profile)
            return profile
        } else {
            let profile = ServerProfile()
            cp(profile)
            return profile
        }
    }

    func toDictionary() -> [String:AnyObject] {
        var d = [String:AnyObject]()
        d["Id"] = uuid as AnyObject?
        d["ServerHost"] = serverHost as AnyObject?
        d["ServerPort"] = NSNumber(value: serverPort as UInt16)
        d["Method"] = method as AnyObject?
        d["Password"] = password as AnyObject?
        d["Remark"] = remark as AnyObject?
        d["Plugin"] = plugin as AnyObject
        d["PluginOptions"] = pluginOptions as AnyObject
        return d
    }

    func toJsonConfig() -> [String: AnyObject] {
        var conf: [String: AnyObject] = ["password": password as AnyObject,
                                         "method": method as AnyObject,]
        
        let defaults = UserDefaults.standard
        conf["local_port"] = NSNumber(value: UInt16(defaults.integer(forKey: "LocalSocks5.ListenPort")) as UInt16)
        conf["local_address"] = defaults.string(forKey: "LocalSocks5.ListenAddress") as AnyObject?
        conf["timeout"] = NSNumber(value: UInt32(defaults.integer(forKey: "LocalSocks5.Timeout")) as UInt32)
        conf["server"] = serverHost as AnyObject
        conf["server_port"] = NSNumber(value: serverPort as UInt16)

        if !plugin.isEmpty {
            // all plugin binaries should be located in the plugins dir
            // so that we don't have to mess up with PATH envvars
            conf["plugin"] = "plugins/\(plugin)" as AnyObject
            conf["plugin_opts"] = pluginOptions as AnyObject
        }

        return conf
    }
    
    func debugString() -> String {
        var buf = ""
        print("ServerHost=\(String(repeating: "*", count: serverHost.count))", to: &buf)
        print("ServerPort=\(serverPort)", to: &buf)
        print("Method=\(method)", to: &buf)
        print("Password=\(String(repeating: "*", count: password.count))", to: &buf)
        print("Plugin=\(plugin)", to: &buf)
        print("PluginOptions=\(pluginOptions)", to: &buf)
        return buf
    }

    func isValid() -> Bool {
        func validateIpAddress(_ ipToValidate: String) -> Bool {

            var sin = sockaddr_in()
            var sin6 = sockaddr_in6()

            if ipToValidate.withCString({ cstring in inet_pton(AF_INET6, cstring, &sin6.sin6_addr) }) == 1 {
                // IPv6 peer.
                return true
            }
            else if ipToValidate.withCString({ cstring in inet_pton(AF_INET, cstring, &sin.sin_addr) }) == 1 {
                // IPv4 peer.
                return true
            }

            return false;
        }

        func validateDomainName(_ value: String) -> Bool {
            let validHostnameRegex = "^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9])\\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\\-]*[A-Za-z0-9])$"

            if (value.range(of: validHostnameRegex, options: .regularExpression) != nil) {
                return true
            } else {
                return false
            }
        }

        if !(validateIpAddress(serverHost) || validateDomainName(serverHost)){
            return false
        }

        if password.isEmpty {
            return false
        }

        return true
    }

    private func makeLegacyURL() -> URL? {
        var url = URLComponents()

        url.host = serverHost
        url.user = method
        url.password = password
        url.port = Int(serverPort)

        url.fragment = remark

        let parts = url.string?.replacingOccurrences(
            of: "//", with: "",
            options: String.CompareOptions.anchored, range: nil)

        let base64String = parts?.data(using: String.Encoding.utf8)?
            .base64EncodedString(options: Data.Base64EncodingOptions())
        if var s = base64String {
            s = s.trimmingCharacters(in: CharacterSet(charactersIn: "="))
            return Foundation.URL(string: "ss://\(s)")
        }
        return nil
    }

    func URL(legacy: Bool = false) -> URL? {
        // If you want the URL from <= 1.5.1
        if (legacy) {
            return self.makeLegacyURL()
        }

        guard let rawUserInfo = "\(method):\(password)".data(using: .utf8) else {
            return nil
        }
        let userInfo = rawUserInfo.base64EncodedString()

        var items: [URLQueryItem] = []
        if !plugin.isEmpty {
            let value = "\(plugin);\(pluginOptions)"
            items.append(URLQueryItem(name: "plugin", value: value))
        }

        var comps = URLComponents()

        comps.scheme = "ss"
        comps.host = serverHost
        comps.port = Int(serverPort)
        comps.user = userInfo
        comps.path = "/"  // This is required by SIP0002 for URLs with fragment or query
        comps.fragment = remark
        comps.queryItems = items

        let url = try? comps.asURL()

        return url
    }
    
    func title() -> String {
        if remark.isEmpty {
            return "\(serverHost):\(serverPort)"
        } else {
            return "\(String(remark.prefix(24))) (\(serverHost):\(serverPort))"
        }
    }
    
}
