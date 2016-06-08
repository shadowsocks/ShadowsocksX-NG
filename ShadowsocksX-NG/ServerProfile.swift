//
//  ServerProfile.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/6.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Cocoa



class ServerProfile: NSObject {
    var uuid: String
    
    var serverHost: String = ""
    var serverPort: uint16 = 8379
    var method:String = "aes-128-cfb"
    var password:String = ""
    var remark:String = ""
    var ota: Bool = false // onetime authentication
    
    override init() {
        uuid = NSUUID().UUIDString
    }
    
    init(uuid: String) {
        self.uuid = uuid
    }
    
    static func fromDictionary(data:[String:AnyObject]) -> ServerProfile {
        let cp = {
            (profile: ServerProfile) in
            profile.serverHost = data["ServerHost"] as! String
            profile.serverPort = (data["ServerPort"] as! NSNumber).unsignedShortValue
            profile.method = data["Method"] as! String
            profile.password = data["Password"] as! String
            if let remark = data["Remark"] {
                profile.remark = remark as! String
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
        d["Id"] = uuid
        d["ServerHost"] = serverHost
        d["ServerPort"] = NSNumber(unsignedShort:serverPort)
        d["Method"] = method
        d["Password"] = password
        d["Remark"] = remark
        return d
    }
    
    func toJsonConfig() -> [String: AnyObject] {
        var conf: [String: AnyObject] = ["server": serverHost,
                                         "server_port": NSNumber(unsignedShort: serverPort),
                                         "password": password,
                                         "method": method,]
        
        let defaults = NSUserDefaults.standardUserDefaults()
        conf["local_port"] = NSNumber(unsignedShort: UInt16(defaults.integerForKey("LocalSocks5.ListenPort")))
        conf["local_address"] = defaults.stringForKey("LocalSocks5.ListenAddress")
        conf["timeout"] = NSNumber(unsignedInt: UInt32(defaults.integerForKey("LocalSocks5.Timeout")))
        
        return conf
    }
    
    func isValid() -> Bool {
        func validateIpAddress(ipToValidate: String) -> Bool {
            
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
        
        func validateDomainName(value: String) -> Bool {
            let validHostnameRegex = "^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9])\\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\\-]*[A-Za-z0-9])$"
            
            if (value.rangeOfString(validHostnameRegex, options: .RegularExpressionSearch) != nil) {
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
    
    func URL() -> NSURL? {
        let parts = "\(method):\(password)@\(serverHost):\(serverPort)"
        let base64String = parts.dataUsingEncoding(NSUTF8StringEncoding)?
            .base64EncodedStringWithOptions(NSDataBase64EncodingOptions())
        if var s = base64String {
            s = s.stringByTrimmingCharactersInSet(NSCharacterSet(charactersInString: "="))
            return NSURL(string: "ss://\(s)")
        }
        return nil
    }
}
