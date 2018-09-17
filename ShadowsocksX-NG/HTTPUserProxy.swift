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
        
        apiserver.addHandler(forMethod: "POST", path: "/toggle", request: GCDWebServerRequest.self, processBlock: {request in
            self.appdeleget.doToggleRunning(showToast: false)
            return GCDWebServerDataResponse(jsonObject: ["status":1], contentType: "json")
        })
        
        apiserver.addHandler(forMethod: "GET", path: "/servers", request: GCDWebServerRequest.self, processBlock: {request in
            
            var data = [[String:String]]()
            
            for each in self.SerMgr.profiles{
                data.append(["id":each.uuid,"remark":each.remark,
                             "active":self.SerMgr.activeProfileId == each.uuid ? "1" : "0"])
            }
            
            return GCDWebServerDataResponse(jsonObject: data, contentType: "json")
        })
        
        apiserver.addHandler(forMethod: "POST", path: "/servers", request: GCDWebServerURLEncodedFormRequest.self, processBlock: {request in
            
            let uuid = ((request as! GCDWebServerURLEncodedFormRequest).arguments["id"])as? String
            for each in self.SerMgr.profiles{
                if (each.uuid == uuid) {
                    self.appdeleget.changeServer(uuid: uuid!)
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
