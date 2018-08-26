//
//  ApiServer.swift
//  ShadowsocksX-R
//
//  Created by CYC on 2016/10/9.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Foundation
import GCDWebServer



class ApiMgr{
    static let shard = ApiMgr()
    
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
        apiserver.addHandler(forMethod: "GET", path: "/servers", request: GCDWebServerRequest.self, processBlock: {request in
            return GCDWebServerDataResponse(jsonObject: self.serverList(), contentType: "json")
        })
        
        apiserver.addHandler(forMethod: "POST", path: "/toggle", request: GCDWebServerRequest.self, processBlock: {request in
            self.toggle()
            return GCDWebServerDataResponse(jsonObject: ["Status":1], contentType: "json")
        })
        
        apiserver.addHandler(forMethod: "POST", path: "/mode", request: GCDWebServerURLEncodedFormRequest.self, processBlock: {request in
            if let arg = ((request as! GCDWebServerURLEncodedFormRequest).arguments["value"])as? String
            {
                switch arg{
                case "auto":self.defaults.setValue("auto", forKey: "ShadowsocksRunningMode")
                case "global":self.defaults.setValue("global", forKey: "ShadowsocksRunningMode")
                case "manual":self.defaults.setValue("manual", forKey: "ShadowsocksRunningMode")
                default: return GCDWebServerDataResponse(jsonObject: ["Status":0], contentType: "json")
                }
                DispatchQueue.global().async(execute: {
                    self.appdeleget.updateRunningModeMenu()
                });
                return GCDWebServerDataResponse(jsonObject: ["Status":1], contentType: "json")
            }
            return GCDWebServerDataResponse(jsonObject: ["Status":0], contentType: "json")
        })
        
        apiserver.addHandler(forMethod: "GET", path: "/mode", request: GCDWebServerRequest.self, processBlock: {request in
            if let current = self.defaults.string(forKey: "ShadowsocksRunningMode"){
                return GCDWebServerDataResponse(jsonObject: ["mode":current], contentType: "json")
            }
            return GCDWebServerDataResponse(jsonObject: ["mode":"unknow"], contentType: "json")
        })
        
        apiserver.addHandler(forMethod: "GET", path: "/status", request: GCDWebServerRequest.self, processBlock: {request in
            let current = self.defaults.bool(forKey: "ShadowsocksOn")
            return GCDWebServerDataResponse(jsonObject: ["enable":current], contentType: "json")
        })
        
        apiserver.addHandler(forMethod: "POST", path: "/servers", request: GCDWebServerURLEncodedFormRequest.self, processBlock: {request in
            let uuid = ((request as! GCDWebServerURLEncodedFormRequest).arguments["uuid"])as? String
            if uuid == nil{return GCDWebServerDataResponse(jsonObject: ["status":0], contentType: "json")}
            self.changeServ(uuid: uuid!)
            return GCDWebServerDataResponse(jsonObject: ["status":1], contentType: "json")
        })
    }
    
    func serverList() -> [[String:String]]{
        var data = [[String:String]]()
        for each in self.SerMgr.profiles{
            data.append(["id":each.uuid,"note":each.remark,
                         "active":SerMgr.activeProfileId == each.uuid ? "1" : "0"])
        }
        return data
    }
    
    func toggle(){
        var isOn = self.defaults.bool(forKey: "ShadowsocksOn")
        isOn = !isOn
        self.defaults.set(isOn, forKey: "ShadowsocksOn")
        appdeleget.applyConfig()
        DispatchQueue.global().async(execute:{
            self.appdeleget.updateMainMenu()
        });
    }
    
    func changeServ(uuid:String){
        for each in SerMgr.profiles{
            if each.uuid == uuid{
                SerMgr.setActiveProfiledId(uuid)
                appdeleget.updateServersMenu()
                SyncSSLocal()
                return
            }
        }
    }
}
