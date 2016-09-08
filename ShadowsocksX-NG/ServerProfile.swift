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
    var ssrProtocol:String = "origin"
    var ssrProtocolParam:String = ""
    var ssrObfs:String = "plain"
    var ssrObfsParam:String = ""
    
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
            if let ota = data["OTA"] {
                profile.ota = ota as! Bool
            }
            if let ssrObfs = data["ssrObfs"] {
                profile.ssrObfs = ssrObfs as! String
            }
            if let ssrObfsParam = data["ssrObfsParam"] {
                profile.ssrObfsParam = ssrObfsParam as! String
            }
            if let ssrProtocol = data["ssrProtocol"] {
                profile.ssrProtocol = ssrProtocol as! String
            }
            if let ssrProtocolParam = data["ssrProtocolParam"]{
                profile.ssrProtocolParam = ssrProtocolParam as! String
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
        d["OTA"] = ota
        d["ssrProtocol"] = ssrProtocol
        d["ssrProtocolParam"] = ssrProtocolParam
        d["ssrObfs"] = ssrObfs
        d["ssrObfsParam"] = ssrObfsParam
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
        conf["auth"] = NSNumber(bool: ota)
        if(!ssrObfs.isEmpty){
            conf["protocol"] = ssrProtocol
            conf["protocol_param"] = ssrProtocolParam
            conf["obfs"] = ssrObfs
            conf["obfs_param"] = ssrObfsParam
        }
        
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
        
        if (ssrProtocol.isEmpty && !ssrObfs.isEmpty)||(!ssrProtocol.isEmpty && ssrObfs.isEmpty){
            return false
        }
        
        return true
    }
    
    func URL() -> NSURL? {
        if(ssrObfs=="plain"){
            let parts = "\(method):\(password)@\(serverHost):\(serverPort)"
            let base64String = parts.dataUsingEncoding(NSUTF8StringEncoding)?
                .base64EncodedStringWithOptions(NSDataBase64EncodingOptions())
            if var s = base64String {
                s = s.stringByTrimmingCharactersInSet(NSCharacterSet(charactersInString: "="))
                return NSURL(string: "ss://\(s)")
            }
        }else{
            let firstParts = "\(serverHost):\(serverPort):\(ssrProtocol):\(method):\(ssrObfs):"
            let secondParts = "\(password)"
            //base64(abc.xyz:12345:auth_sha1_v2:rc4-md5:tls1.2_ticket_auth:{base64(password)}/?obfsparam={base64(混淆参数(网址))}&remarks={base64(节点名称)})
            let base64PasswordString = secondParts.dataUsingEncoding(NSUTF8StringEncoding)?
                .base64EncodedStringWithOptions(NSDataBase64EncodingOptions())
            
            let base64ssrObfsParamString = ssrObfsParam.dataUsingEncoding(NSUTF8StringEncoding)?
                .base64EncodedStringWithOptions(NSDataBase64EncodingOptions())
          
            let base64RemarkString = remark.dataUsingEncoding(NSUTF8StringEncoding)?
                .base64EncodedStringWithOptions(NSDataBase64EncodingOptions())
            
            var s = firstParts + base64PasswordString! + "/?" + "obfsparam=" + base64ssrObfsParamString! + "&remarks=" + base64RemarkString!
            s = (s.dataUsingEncoding(NSUTF8StringEncoding)?
                .base64EncodedStringWithOptions(NSDataBase64EncodingOptions()))!
            return NSURL(string: "ssr://\(s)")
        }
        return nil
    }
}
