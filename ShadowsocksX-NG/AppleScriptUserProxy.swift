//
//  AppleScriptCommand.swift
//  ShadowsocksX-NG
//
//  Created by melonEater on 2018/9/6.
//  Copyright © 2018 qiuyuzhou. All rights reserved.
//

import Cocoa


class AppleScriptUserProxy: NSScriptCommand {
    let appdeleget = NSApplication.shared.delegate as! AppDelegate
    let SerMgr = ServerProfileManager.instance

    override func performDefaultImplementation() -> Any? {
        switch(self.commandDescription.commandName) {
        case "isRunning":
            return isRunning()
        case "toggle":
            toggle()
        case "mode":
            return getMode()
        case "change mode":
            changeMode(mode: self.directParameter as! String)
        case "servers":
            return getServerList();
        case "change server":
            setServer(remark: self.directParameter as! String)
        default:
            return nil;
        }
        return nil
    }
    
    func toggle() {
        self.appdeleget.doToggleRunning(showToast: false)
    }
    
    func isRunning() -> Bool {
        let isOn = UserDefaults.standard.bool(forKey: "ShadowsocksOn")
        return isOn
    }
    
    func getMode() -> String {
        return UserDefaults.standard.string(forKey: "ShadowsocksRunningMode") as! String
    }
    
    func changeMode(mode:String) {
        appdeleget.changeMode(mode: mode)
    }

    func getServerList() -> [String] {
        var data = [String]()

        for each in self.SerMgr.profiles{
            data.append(each.remark)
        }
        
        return data
    }
    
    func setServer(remark: String) {
        for each in self.SerMgr.profiles{
            if (each.remark == remark) {
                self.appdeleget.changeServer(uuid: each.uuid)
                return
            }
        }
    }
}

