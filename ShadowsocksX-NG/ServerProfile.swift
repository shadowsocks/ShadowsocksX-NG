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
    
    var ssrProtocol:String = "origin"
    var ssrProtocolParam:String = ""
    var ssrObfs:String = "plain"
    var ssrObfsParam:String = ""
    var ssrGroup: String = ""
    
    var latency:String?
    
    override init() {
        uuid = UUID().uuidString
    }
    
    init(uuid: String) {
        self.uuid = uuid
    }
    
    static func fromDictionary(_ data:[String:AnyObject]) -> ServerProfile {
        let cp = {
            (profile: ServerProfile) in
            profile.serverHost = data["ServerHost"] as! String
            profile.serverPort = (data["ServerPort"] as! NSNumber).uint16Value
            profile.method = data["Method"] as! String
            profile.password = data["Password"] as! String
            
            if let remark = data["Remark"] {
                profile.remark = remark as! String
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
            if let ssrGroup = data["ssrGroup"]{
                profile.ssrGroup = ssrGroup as! String
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
        d["ssrProtocol"] = ssrProtocol as AnyObject?
        d["ssrProtocolParam"] = ssrProtocolParam as AnyObject?
        d["ssrObfs"] = ssrObfs as AnyObject?
        d["ssrObfsParam"] = ssrObfsParam as AnyObject?
        d["ssrGroup"] = ssrGroup as AnyObject?
        return d
    }
    
    func toJsonConfig() -> [String: AnyObject] {
        // supply json file for ss-local only export vital param
        var conf: [String: AnyObject] = ["server": serverHost as AnyObject,
                                         "server_port": NSNumber(value: serverPort as UInt16),
                                         "password": password as AnyObject,
                                         "method": method as AnyObject,]
        
        let defaults = UserDefaults.standard
        conf["local_port"] = NSNumber(value: UInt16(defaults.integer(forKey: "LocalSocks5.ListenPort")) as UInt16)
        conf["local_address"] = defaults.string(forKey: "LocalSocks5.ListenAddress") as AnyObject?
        conf["timeout"] = NSNumber(value: UInt32(defaults.integer(forKey: "LocalSocks5.Timeout")) as UInt32)
        
        if(!ssrObfs.isEmpty){
            conf["protocol"] = ssrProtocol as AnyObject?
            conf["protocol_param"] = ssrProtocolParam as AnyObject?// do not muta here
            conf["obfs"] = ssrObfs as AnyObject?
            conf["obfs_param"] = ssrObfsParam as AnyObject?
        }
        
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
        
        if (ssrProtocol.isEmpty && !ssrObfs.isEmpty)||(!ssrProtocol.isEmpty && ssrObfs.isEmpty){
            return false
        }
        
        return true
    }
    
    func URL() -> Foundation.URL? {
        if(ssrObfs=="plain"){
            let parts = "\(method):\(password)@\(serverHost):\(serverPort)"
            let base64String = parts.data(using: String.Encoding.utf8)?
                .base64EncodedString(options: NSData.Base64EncodingOptions())
            if var s = base64String {
                s = s.trimmingCharacters(in: CharacterSet(charactersIn: "="))
                return Foundation.URL(string: "ss://\(s)")
            }
        }else{
            let firstParts = "\(serverHost):\(serverPort):\(ssrProtocol):\(method):\(ssrObfs):"
            let secondParts = "\(password)"
            // ssr:// + base64(abc.xyz:12345:auth_sha1_v2:rc4-md5:tls1.2_ticket_auth:{base64(password)}/?obfsparam={base64(混淆参数(网址))}&protoparam={base64(混淆协议)}&remarks={base64(节点名称)}&group={base64(分组名)})
            let base64PasswordString = encode64(secondParts)
            let base64ssrObfsParamString = encode64(ssrObfsParam)
            let base64ssrProtocolParamString = encode64(ssrProtocolParam)
            let base64RemarkString = encode64(remark)
            let base64GroupString = encode64(ssrGroup)
            
            var s = firstParts + base64PasswordString! + "/?" + "obfsparam=" + base64ssrObfsParamString! + "&protoparam=" + base64ssrProtocolParamString! + "&remarks=" + base64RemarkString! + "&group=" + base64GroupString!
            s = encode64(s)
            return Foundation.URL(string: "ssr://\(s)")
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
