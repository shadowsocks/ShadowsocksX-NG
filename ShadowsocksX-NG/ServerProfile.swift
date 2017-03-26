//
//  ServerProfile.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/6.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Cocoa


class ServerProfile: NSObject, NSCopying {
    
    var uuid: String

    var serverHost: String = ""
    var serverPort: uint16 = 8379
    var method:String = "aes-128-cfb"
    var password:String = ""
    var remark:String = ""
    var ota: Bool = false // onetime authentication
    
    var enabledKcptun: Bool = false
    var kcptunProfile = KcptunProfile()
    
    override init() {
        uuid = UUID().uuidString
    }

    init(uuid: String) {
        self.uuid = uuid
    }

    convenience init?(url: URL?) {
        self.init()

        func padBase64(string: String) -> String {
            var length = string.characters.count
            if length % 4 == 0 {
                return string
            } else {
                length = 4 - length % 4 + length
                return string.padding(toLength: length, withPad: "=", startingAt: 0)
            }
        }

        func decodeUrl(url: URL?) -> String? {
            guard let urlStr = url?.absoluteString else {
                return nil
            }
            let index = urlStr.index(urlStr.startIndex, offsetBy: 5)
            let encodedStr = urlStr.substring(from: index)
            guard let data = Data(base64Encoded: padBase64(string: encodedStr)) else {
                return url?.absoluteString
            }
            guard let decoded = String(data: data, encoding: String.Encoding.utf8) else {
                return nil
            }
            let s = decoded.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
            return "ss://\(s)"
        }

        guard let decodedUrl = decodeUrl(url: url) else {
            return nil
        }
        guard var parsedUrl = URLComponents(string: decodedUrl) else {
            return nil
        }
        guard let host = parsedUrl.host, let port = parsedUrl.port,
            let method = parsedUrl.user, let password = parsedUrl.password else {
            return nil
        }

        self.serverHost = host
        self.serverPort = UInt16(port)
        self.method = method.lowercased()
        self.password = password

        remark = parsedUrl.queryItems?
            .filter({ $0.name == "Remark" }).first?.value ?? ""
        if let otaStr = parsedUrl.queryItems?
            .filter({ $0.name == "OTA" }).first?.value {
            ota = NSString(string: otaStr).boolValue
        }
        if let enabledKcptunStr = parsedUrl.queryItems?
            .filter({ $0.name == "Kcptun" }).first?.value {
            enabledKcptun = NSString(string: enabledKcptunStr).boolValue
        }
        
        if enabledKcptun {
            if let items = parsedUrl.queryItems {
                self.kcptunProfile.loadUrlQueryItems(items: items)
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
        copy.ota = self.ota
        
        copy.enabledKcptun = self.enabledKcptun
        copy.kcptunProfile = self.kcptunProfile.copy() as! KcptunProfile
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
            if let ota = data["OTA"] {
                profile.ota = ota as! Bool
            }
            if let enabledKcptun = data["EnabledKcptun"] {
                profile.enabledKcptun = enabledKcptun as! Bool
            }
            if let kcptunData = data["KcptunProfile"] {
                profile.kcptunProfile =  KcptunProfile.fromDictionary(kcptunData as! [String:Any?])
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
        d["OTA"] = ota as AnyObject?
        d["EnabledKcptun"] = NSNumber(value: enabledKcptun)
        d["KcptunProfile"] = kcptunProfile.toDictionary() as AnyObject
        return d
    }

    func toJsonConfig() -> [String: AnyObject] {
        var conf: [String: AnyObject] = ["password": password as AnyObject,
                                         "method": method as AnyObject,]
        
        let defaults = UserDefaults.standard
        conf["local_port"] = NSNumber(value: UInt16(defaults.integer(forKey: "LocalSocks5.ListenPort")) as UInt16)
        conf["local_address"] = defaults.string(forKey: "LocalSocks5.ListenAddress") as AnyObject?
        conf["timeout"] = NSNumber(value: UInt32(defaults.integer(forKey: "LocalSocks5.Timeout")) as UInt32)
        if ota {
            conf["auth"] = NSNumber(value: ota as Bool)
        }
        
        if enabledKcptun {
            let localHost = defaults.string(forKey: "Kcptun.LocalHost")
            let localPort = uint16(defaults.integer(forKey: "Kcptun.LocalPort"))
            
            conf["server"] = localHost as AnyObject
            conf["server_port"] = NSNumber(value: localPort as UInt16)
        } else {
            conf["server"] = serverHost as AnyObject
            conf["server_port"] = NSNumber(value: serverPort as UInt16)
        }

        return conf
    }
    
    func toKcptunJsonConfig() -> [String: AnyObject] {
        var conf = kcptunProfile.toJsonConfig()
        conf["remoteaddr"] = "\(serverHost):\(serverPort)" as AnyObject
        return conf
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

    func URL() -> Foundation.URL? {
        var url = URLComponents()

        url.host = serverHost
        url.user = method
        url.password = password
        url.port = Int(serverPort)

        url.queryItems = [URLQueryItem(name: "Remark", value: remark),
                          URLQueryItem(name: "OTA", value: ota.description)]
        if enabledKcptun {
            url.queryItems?.append(contentsOf: [
                URLQueryItem(name: "Kcptun", value: enabledKcptun.description),
                ])
            url.queryItems?.append(contentsOf: kcptunProfile.urlQueryItems())
        }

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
    
    func title() -> String {
        if remark.isEmpty {
            return "\(serverHost):\(serverPort)"
        } else {
            return "\(remark) (\(serverHost):\(serverPort))"
        }
    }
}
