//
//  ApiServer.swift
//  ShadowsocksX-R
//
//  Created by CYC on 2016/10/9.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Foundation
import GCDWebServer



class HTTPUserProxy{
    static let shard = HTTPUserProxy()
    
    let apiserver = GCDWebServer()
    let SerMgr = ServerProfileManager.instance
    let defaults = UserDefaults.standard
    let appdeleget = NSApplication.shared.delegate as! AppDelegate
    let api_port:UInt = 9528
    
    func start(){
        setRouter()
        do{
            try apiserver.start(options: [GCDWebServerOption_Port:api_port,"BindToLocalhost":true])
        }catch{
            NSLog("Error:ApiServ start fail")
        }
    }
    
    func setRouter(){
        apiserver.addHandler(forMethod: "GET", path: "/status", request: GCDWebServerRequest.self, processBlock: {request in
            let isOn = self.defaults.bool(forKey: "ShadowsocksOn")
            return GCDWebServerDataResponse(jsonObject: ["enable":isOn], contentType: "json")
        })
        
        apiserver.addHandler(forMethod: "POST", path: "/status", request: GCDWebServerURLEncodedFormRequest.self, processBlock: {request in
            if let enable = ((request as! GCDWebServerURLEncodedFormRequest).arguments["enable"])as? String {
                if (enable != "true" && enable != "false") {
                    return GCDWebServerDataResponse(jsonObject: ["status":0], contentType: "json")
                }
                
                let isOn = self.defaults.bool(forKey: "ShadowsocksOn")
                if (Bool(enable) != isOn) {
                    self.appdeleget.doToggleRunning(showToast: false)
                }
            }
            else {
                self.appdeleget.doToggleRunning(showToast: false)
            }
            return GCDWebServerDataResponse(jsonObject: ["status":1], contentType: "json")
        })
        
        apiserver.addHandler(forMethod: "GET", path: "/server/list", request: GCDWebServerRequest.self, processBlock: {request in
            
            var data = [[String:Any]]()
            
            for each in self.SerMgr.profiles{
                data.append(each.toDictionary())
            }
            
            return GCDWebServerDataResponse(jsonObject: data, contentType: "json")
        })
        
        apiserver.addHandler(forMethod: "GET", path: "/server/current", request: GCDWebServerRequest.self, processBlock: {request in
            
            return GCDWebServerDataResponse(jsonObject: ["Id":self.SerMgr.activeProfileId], contentType: "json")
        })
        
        apiserver.addHandler(forMethod: "POST", path: "/server/current", request: GCDWebServerURLEncodedFormRequest.self, processBlock: {request in
            
            let uuid = ((request as! GCDWebServerURLEncodedFormRequest).arguments["Id"])as? String
            for each in self.SerMgr.profiles{
                if (each.uuid == uuid) {
                    self.appdeleget.changeServer(uuid: uuid!)
                    return GCDWebServerDataResponse(jsonObject: ["status":1], contentType: "json")
                    
                }
            }
            return GCDWebServerDataResponse(jsonObject: ["status":0], contentType: "json")
        })
        
        apiserver.addHandler(forMethod: "POST", path: "/server", request: GCDWebServerURLEncodedFormRequest.self, processBlock: {request in
            
            var data = ((request as! GCDWebServerURLEncodedFormRequest).arguments) as! [String: Any]
            data["ServerPort"] = Double(data["ServerPort"] as! String)
            let id = data["Id"] as? String
            if (id != nil) {
                for each in self.SerMgr.profiles{
                    if (each.uuid == id) {
                        ServerProfile.copy(fromDict: data, toProfile: each)
                        if (each.isValid()) {
                            self.SerMgr.save()
                            self.appdeleget.updateServersMenu()
                            return GCDWebServerDataResponse(jsonObject: ["status":1], contentType: "json")
                        }
                    }
                }
            }
            else {
                let profile = ServerProfile.fromDictionary(data)
                if (profile.isValid()) {
                    self.SerMgr.profiles.append(profile)
                    self.SerMgr.save()
                    self.appdeleget.updateServersMenu()
                    return GCDWebServerDataResponse(jsonObject: ["status":1], contentType: "json")
                }
            }
            
            return GCDWebServerDataResponse(jsonObject: ["status":0], contentType: "json")
        })
        
        apiserver.addHandler(forMethod: "DELETE", path: "/server", request: GCDWebServerRequest.self
            , processBlock: {request in
                
                let uuid = (request.query?["Id"])as! String
                
                if (uuid == self.SerMgr.activeProfileId) {
                    return GCDWebServerDataResponse(jsonObject: ["status":0], contentType: "json")
                }
                
                for i in 0..<self.SerMgr.profiles.count{
                    if (self.SerMgr.profiles[i].uuid == uuid) {
                        self.SerMgr.profiles.remove(at: i)
                        
                        self.SerMgr.save()
                        self.appdeleget.updateServersMenu()
                        
                        return GCDWebServerDataResponse(jsonObject: ["status":1], contentType: "json")
                    }
                }
                
                return GCDWebServerDataResponse(jsonObject: ["status":0], contentType: "json")
        })
        
        apiserver.addHandler(forMethod: "GET", path: "/mode", request: GCDWebServerRequest.self, processBlock: {request in
            if let current = self.defaults.string(forKey: "ShadowsocksRunningMode"){
                return GCDWebServerDataResponse(jsonObject: ["mode":current], contentType: "json")
            }
            return GCDWebServerDataResponse(jsonObject: ["mode":"unknow"], contentType: "json")
        })
        
        apiserver.addHandler(forMethod: "POST", path: "/mode", request: GCDWebServerURLEncodedFormRequest.self, processBlock: {request in
            let arg = ((request as! GCDWebServerURLEncodedFormRequest).arguments["mode"])as? String
            
            if (arg != "auto" && arg != "global" && arg != "manual") {
                return GCDWebServerDataResponse(jsonObject: ["status":0], contentType: "json")
            }
            
            self.appdeleget.changeMode(mode: arg!)
            
            return GCDWebServerDataResponse(jsonObject: ["status":1], contentType: "json")
        })
    }
}
