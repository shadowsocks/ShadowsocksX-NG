//
//  HTTPUserProxy.swift
//  ShadowsocksX-R
//
//  Created by CYC on 2016/10/9.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Foundation
import GCDWebServer

class HTTPUserProxy{
    static let shard = HTTPUserProxy()
    
    let adapter = APIAdapter()
    let v = Validator()
    
    let server = GCDWebServer()
    let api_port:UInt = 9528
    
    let UUID_REGEX:String = "[\\w\\d-]*"
    
    func start(){
        setRouter()
        do{
            try server.start(options: [GCDWebServerOption_Port:api_port,"BindToLocalhost":true])
        }catch{
            NSLog("Error:HTTPUserProxy start fail")
        }
    }
    
    func setRouter(){
        // GET /status
        addHandler_getStatus()
        // PUT /status
        addHandler_setStatus()

        // GET /servers
        addHandler_getServerList()
        // GET /current
        addHandler_getCurrentServer()
        // PUT /current
        addHandler_setCurrentServer()
        // POST /servers
        addHandler_addServer()
        // PATCH /servers/{uuid}
        addHandler_modifyServer()
        // DELETE /servers/{uuid}
        addHandler_deleteServer()
        
        // GET /mode
        addHandler_getMode()
        // PUT /mode
        addHandler_setMode()
    }
    
    func addHandler_getStatus() {
        server.addHandler(forMethod: "GET", path: "/status", request: GCDWebServerRequest.self, processBlock: {request in
            return GCDWebServerDataResponse(jsonObject: ["Enable":self.adapter.getStatus()], contentType: "json")
        })
    }
    
    func addHandler_setStatus() {
        server.addHandler(forMethod: "PUT", path: "/status", request: GCDWebServerURLEncodedFormRequest.self, processBlock: {request in
            if let targetStatus_str = (request as? GCDWebServerURLEncodedFormRequest)?.arguments["Enable"] as? String{
                if let targetStatus = Bool(targetStatus_str) {
                    self.adapter.setStatus(status: targetStatus)
                    return GCDWebServerResponse()
                }
            }
            else {
                self.adapter.toggleStatus()
                return GCDWebServerResponse()
            }
            return GCDWebServerResponse(statusCode: 400)
        })
    }
    
    func addHandler_getServerList() {
        server.addHandler(forMethod: "GET", path: "/servers", request: GCDWebServerRequest.self, processBlock: {request in
            return GCDWebServerDataResponse(jsonObject: self.adapter.getServerList(), contentType: "json")
        })
    }
    
    func addHandler_getCurrentServer() {
        server.addHandler(forMethod: "GET", path: "/current", request: GCDWebServerRequest.self, processBlock: {request in
            if let activeId = self.adapter.getCurrentServerId() {
                return GCDWebServerDataResponse(jsonObject: self.adapter.getServer(uuid: activeId)!, contentType: "json")
            }
            else {
                return GCDWebServerResponse(statusCode: 404);
            }
        })
    }
    
    func addHandler_setCurrentServer() {
        server.addHandler(forMethod: "PUT", path: "/current", request: GCDWebServerURLEncodedFormRequest.self, processBlock: {request in
            
            if let targetId = (request as? GCDWebServerURLEncodedFormRequest)?.arguments["Id"] as? String{
                if self.adapter.getServer(uuid: targetId) != nil {
                    self.adapter.setCurrentServer(uuid: targetId);
                    return GCDWebServerResponse()
                }
            }
            return GCDWebServerResponse(statusCode: 400)
        })
    }
    
    func addHandler_addServer() {
        server.addHandler(forMethod: "POST", path: "/servers", request: GCDWebServerURLEncodedFormRequest.self, processBlock: {request in
            if var server = ((request as? GCDWebServerURLEncodedFormRequest)?.arguments) as? [String: Any] {
                if (server["ServerPort"] != nil) {
                    server["ServerPort"] = UInt16(server["ServerPort"] as! String)
                    if (Validator.integrity(server) && Validator.existAttributes(server)) { // validate
                        self.adapter.addServer(server: server)
                        return GCDWebServerResponse();
                    }
                }
            }
            return GCDWebServerResponse(statusCode: 400)
        });
    }
    
    func addHandler_modifyServer() {
        server.addHandler(forMethod: "PATCH", pathRegex: "/servers/"+self.UUID_REGEX, request: GCDWebServerURLEncodedFormRequest.self, processBlock: {request in
            let id = String(request.path.dropFirst("/servers/".count))
            if var server = ((request as? GCDWebServerURLEncodedFormRequest)?.arguments) as? [String: Any] {
                if (server["ServerPort"] != nil) {
                    server["ServerPort"] = UInt16(server["ServerPort"] as! String)
                }
                if (self.adapter.getServer(uuid: id) != nil) {
                    if (Validator.existAttributes(server)) {
                        if (self.adapter.getCurrentServerId() != id) {
                            self.adapter.modifyServer(uuid: id, server: server)
                            return GCDWebServerResponse()
                        }
                        else {
                            return GCDWebServerResponse(statusCode: 400);
                        }
                    }
                } else {
                    return GCDWebServerResponse(statusCode: 404)
                }
            }
            return GCDWebServerResponse(statusCode: 400)
        })
    }
    
    func addHandler_deleteServer() {
        server.addHandler(forMethod: "DELETE", pathRegex: "/servers/"+self.UUID_REGEX, request: GCDWebServerRequest.self
            , processBlock: {request in
                let id = String(request.path.dropFirst("/servers/".count))
                if((self.adapter.getServer(uuid: id)) != nil) {
                    if (self.adapter.getCurrentServerId() != id) {
                        self.adapter.deleteServer(uuid: id)
                        return GCDWebServerResponse()
                    } else {
                        return GCDWebServerResponse(statusCode: 400)
                    }
                }
                else {
                    return GCDWebServerResponse(statusCode: 404)
                }
        })
    }
    
    func addHandler_getMode() {
        server.addHandler(forMethod: "GET", path: "/mode", request: GCDWebServerRequest.self, processBlock: {request in
            return GCDWebServerDataResponse(jsonObject: ["Mode":self.adapter.getMode().rawValue], contentType: "json")
        })
    }
    
    func addHandler_setMode() {
        server.addHandler(forMethod: "PUT", path: "/mode", request: GCDWebServerURLEncodedFormRequest.self, processBlock: {request in
            if let mode_str = (request as? GCDWebServerURLEncodedFormRequest)?.arguments["Mode"] as? String{
                if let mode = APIAdapter.Mode(rawValue: mode_str) {
                    self.adapter.setMode(mode: mode);
                    
                    return GCDWebServerResponse()
                }
            }
            return GCDWebServerResponse(statusCode: 400)
        })
    }
}

class APIAdapter {
    enum Mode:String {case auto="auto", global="global", manual="manual"};

    let SerMgr = ServerProfileManager.instance
    let defaults = UserDefaults.standard
    let appdeleget = NSApplication.shared.delegate as! AppDelegate
    
    func getStatus()->Bool {
        return self.defaults.bool(forKey: "ShadowsocksOn");
    }
    
    func setStatus(status:Bool) {
        if (status == self.defaults.bool(forKey: "ShadowsocksOn")) {
            return;
        }
        else {
            appdeleget.doToggleRunning(showToast: false)
        }
    }
    
    func toggleStatus() {
        appdeleget.doToggleRunning(showToast: false)
    }
    
    func getServerList()->[Dictionary<String, Any>] {
        return self.SerMgr.profiles.map {$0.toDictionary()}
    }
    
    func getCurrentServerId()->String? {
        return self.SerMgr.activeProfileId;
    }
    
    func setCurrentServer(uuid:String) {
        self.SerMgr.setActiveProfiledId(uuid)
        self.appdeleget.updateServersMenu()
        SyncSSLocal()
        self.appdeleget.applyConfig()
        self.appdeleget.updateRunningModeMenu()
    }
    
    func getServer(uuid:String)->Dictionary<String, Any>? {
        if let i = self.SerMgr.profiles.index(where: {$0.uuid == uuid}) {
            return self.SerMgr.profiles[i].toDictionary()
        }
        else {
            return nil;
        }
    }
    
    func addServer(server:Dictionary<String, Any>) {
        let profile = ServerProfile.fromDictionary(server)
        
        self.SerMgr.profiles.append(profile)
        self.SerMgr.save()
        self.appdeleget.updateServersMenu()
    }
    
    func modifyServer(uuid:String, server:Dictionary<String, Any>) {
        let index = self.SerMgr.profiles.index(where: {$0.uuid == uuid})!
        let profile = self.SerMgr.profiles[index]
        
        if (server["ServerHost"] != nil) {
            profile.serverHost = server["ServerHost"] as! String;
        }
        if (server["ServerPort"] != nil) {
            profile.serverPort = server["ServerPort"] as! uint16;
        }
        if (server["Method"] != nil) {
            profile.method = server["Method"] as! String;
            
        }
        if (server["Password"] != nil) {
            profile.password = server["Password"] as! String;
        }
        if (server["Remark"] != nil) {
            profile.remark = server["Remark"] as! String;
        }
        if (server["Plugin"] != nil) {
            profile.plugin = server["Plugin"] as! String;
        }
        if (server["PluginOptions"] != nil) {
            profile.pluginOptions = server["PluginOptions"] as! String;
        }
        
        self.SerMgr.save()
        self.appdeleget.updateServersMenu()
    }
    
    func deleteServer(uuid:String) {
        let index = self.SerMgr.profiles.index(where: {$0.uuid == uuid})!
        
        self.SerMgr.profiles.remove(at: index)
        
        self.SerMgr.save()
        self.appdeleget.updateServersMenu()
    }
    
    func getMode()->Mode {
        let mode_str = self.defaults.string(forKey: "ShadowsocksRunningMode");
        switch mode_str {
        case "auto": return .auto
        case "global": return .global;
        case "manual": return .manual
        default:fatalError()
        }
    }
    
    func setMode(mode:Mode) {
        let defaults = UserDefaults.standard
        
        switch mode{
        case .auto:defaults.setValue("auto", forKey: "ShadowsocksRunningMode")
        case .global:defaults.setValue("global", forKey: "ShadowsocksRunningMode")
        case .manual:defaults.setValue("manual", forKey: "ShadowsocksRunningMode")
        }
        
        self.appdeleget.updateRunningModeMenu()
        self.appdeleget.applyConfig()
    }
}

class Validator {
    static func integrity(_ data: Dictionary<String, Any>) -> Bool {
        if (data["ServerHost"] == nil || data["ServerPort"] as? NSNumber == nil
            || data["Method"] == nil || data["Password"] == nil) {
            return false;
        }
        return true;
    }
    
    static func existAttributes(_ server:Dictionary<String, Any>) -> Bool {
        var result = true;
        
        if (server["ServerHost"] != nil) {
            result = result && serverHost(server["ServerHost"] as! String);
        }
        if (server["ServerPort"] != nil) {
            result = result && serverPort(server["ServerPort"] as! uint16);
        }
        if (server["Method"] != nil) {
            result = result && method(server["Method"] as! String);
        }
        if (server["Password"] != nil) {
            result = result && password(server["Password"] as! String);
        }
        if (server["Remark"] != nil) {
            result = result && remark(server["Remark"] as! String);
        }
        if (server["Plugin"] != nil) {
            result = result && plugin(server["Plugin"] as! String);
        }
        if (server["PluginOptions"] != nil) {
            result = result && pluginOptions(server["PluginOptions"] as! String);
        }
        
        return result;
    }
    
    static func serverHost(_ str:String) -> Bool {
        return validateIpAddress(str) || validateDomainName(str);
    }
    
    static func serverPort(_ str:uint16) -> Bool {
        return true;
    }
    
    static func method(_ str:String)  -> Bool {
        // Copy from PreferencesWindowController.swift
        // Better to make valid methods enumeration type.
        return [
            "aes-128-gcm",
            "aes-192-gcm",
            "aes-256-gcm",
            "aes-128-cfb",
            "aes-192-cfb",
            "aes-256-cfb",
            "aes-128-ctr",
            "aes-192-ctr",
            "aes-256-ctr",
            "camellia-128-cfb",
            "camellia-192-cfb",
            "camellia-256-cfb",
            "bf-cfb",
            "chacha20-ietf-poly1305",
            "xchacha20-ietf-poly1305",
            "salsa20",
            "chacha20",
            "chacha20-ietf",
            "rc4-md5",
        ].contains(str);
    }
    
    static func password(_ str:String)  -> Bool  {
        return true;
    }
    
    static func remark(_ str:String)  -> Bool  {
        return true;
    }
    
    static func plugin(_ str:String) -> Bool  {
        return true;
    }
    
    static func pluginOptions(_ str:String)  -> Bool {
        return true;
    }
    
    // Copy from ServerProfile.swift
    private static func validateIpAddress(_ ipToValidate: String) -> Bool {
        
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
    
    // Copy from ServerProfile.swift
    private static func validateDomainName(_ value: String) -> Bool {
        let validHostnameRegex = "^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9])\\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\\-]*[A-Za-z0-9])$"
        
        if (value.range(of: validHostnameRegex, options: .regularExpression) != nil) {
            return true
        } else {
            return false
        }
    }
}
