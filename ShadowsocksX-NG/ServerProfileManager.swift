//
//  ServerProfileManager.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/6. Modified by 秦宇航 17/7/22 
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Cocoa

class ServerProfileManager: NSObject {
    
    static let instance:ServerProfileManager = ServerProfileManager()
    
    var profiles:[ServerProfile]
    var activeProfileId: String?
    
    fileprivate override init() {
        profiles = [ServerProfile]()
        
        let defaults = UserDefaults.standard
        activeProfileId = defaults.string(forKey: "ActiveServerProfileId")
        var didFindActiveProfileId = false
        if let _profiles = defaults.array(forKey: "ServerProfiles") {
            for _profile in _profiles {
                let profile = ServerProfile.fromDictionary(_profile as! [String : AnyObject])
                profiles.append(profile)
                if profile.uuid == activeProfileId {
                    didFindActiveProfileId = true
                }
            }
        }
        if profiles.count == 0{
            let notice = NSUserNotification()
            notice.title = "还没有服务器设定！"
            notice.subtitle = "去设置里面填一下吧，填完记得选择呦~"
            NSUserNotificationCenter.default.deliver(notice)
            return
        }
        if !didFindActiveProfileId {
            activeProfileId = profiles[0].uuid
        }
    }
    
    func setActiveProfiledId(_ id: String) {
        activeProfileId = id
        let defaults = UserDefaults.standard
        defaults.set(id, forKey: "ActiveServerProfileId")
    }
    
    func getActiveProfileId() -> String {
        for p in profiles {
            if p.uuid == activeProfileId {
                return activeProfileId!
            }
        }
        if profiles.count == 0 {return ""}
        return profiles[0].uuid
    }
    
    func save() {
        let defaults = UserDefaults.standard
        var _profiles = [AnyObject]()
        for profile in profiles {
            if profile.isValid() {
                let _profile = profile.toDictionary()
                _profiles.append(_profile as AnyObject)
            }
        }
        defaults.set(_profiles, forKey: "ServerProfiles")
        
        if getActiveProfile() == nil {
            activeProfileId = ""
        }
        
        if getActiveProfileId() != "" {
            defaults.set(getActiveProfileId(), forKey: "ActiveServerProfileId")
            let _ = writeSSLocalConfFile((getActiveProfile()?.toJsonConfig())!)
        } else {
            defaults.removeObject(forKey: "ActiveServerProfileId")
            removeSSLocalConfFile()
        }
    }
    
    func getActiveProfile() -> ServerProfile? {
        if getActiveProfileId() == "" { return nil }
        for p in profiles {
            if p.uuid == getActiveProfileId() {
                return p
            }
        }
        return nil
    }
    
    func isExisted(profile: ServerProfile) -> (Bool, Int){
        for (index, value) in profiles.enumerated() {
            let ret = (value.serverHost == profile.serverHost && value.serverPort == profile.serverPort)
            if ret {
                return (ret, index)
            }
        }
        return (false, -1)
    }
    
    func isDuplicated(profile: ServerProfile) -> (Bool, Int){
        for (index, value) in profiles.enumerated() {
            let ret = value.serverHost == profile.serverHost
                && value.password == profile.password
                && value.serverPort == profile.serverPort
                && value.ssrProtocol == profile.ssrProtocol
                && value.ssrObfs == profile.ssrObfs
                && value.ssrObfsParam == profile.ssrObfsParam
                && value.ssrProtocolParam == profile.ssrProtocolParam
                && value.remark == profile.remark
            if ret {
                return (ret, index)
            }
        }
        return (false, -1)
    }

    func importConfigFile() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Choose Config Json File".localized
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.canChooseFiles = true
        openPanel.becomeKey()
        openPanel.begin { (result) -> Void in
            // TODO not freeze the screen when running import process
            if (result == NSFileHandlingPanelOKButton && (openPanel.url) != nil) {
                let fileManager = FileManager.default
                let filePath:String = (openPanel.url?.path)!
                if (fileManager.fileExists(atPath: filePath) && filePath.hasSuffix("json")) {
                    let data = fileManager.contents(atPath: filePath)
                    let readString = NSString(data: data!, encoding: String.Encoding.utf8.rawValue)!
                    let readStringData = readString.data(using: String.Encoding.utf8.rawValue)
                    
                    let jsonArr1 = try! JSONSerialization.jsonObject(with: readStringData!, options: JSONSerialization.ReadingOptions.mutableContainers) as! NSDictionary
                    
                    for item in jsonArr1.object(forKey: "configs") as! [[String: AnyObject]]{
                        let profile = ServerProfile()
                        profile.serverHost = item["server"] as! String
                        profile.serverPort = UInt16((item["server_port"] as! Int))
                        profile.method = item["method"] as! String
                        profile.password = item["password"] as! String
                        profile.remark = item["remarks"] as! String
                        if(item["group"] != nil){
                            profile.ssrGroup = item["group"] as! String
                        }
                        if (item["obfs"] != nil) {
                            profile.ssrObfs = item["obfs"] as! String
                            profile.ssrProtocol = item["protocol"] as! String
                            if (item["obfsparam"] != nil){
                                profile.ssrObfsParam = item["obfsparam"] as! String
                            }
                            if (item["protocolparam"] != nil){
                                profile.ssrProtocolParam = item["protocolparam"] as! String
                            }
                        }
                        self.profiles.append(profile)
                        self.save()
                    }
                    NotificationCenter.default.post(name: Notification.Name(rawValue: NOTIFY_SERVER_PROFILES_CHANGED), object: nil)
                    let configsCount = (jsonArr1.object(forKey: "configs") as! [[String: AnyObject]]).count
                    let notification = NSUserNotification()
                    notification.title = "Import Server Profile succeed!".localized
                    notification.informativeText = "Successful import \(configsCount) items".localized
                    NSUserNotificationCenter.default
                        .deliver(notification)
                }else{
                    let notification = NSUserNotification()
                    notification.title = "Import Server Profile failed!".localized
                    notification.informativeText = "Invalid config file!".localized
                    NSUserNotificationCenter.default
                        .deliver(notification)
                    return
                }
            }
        }
    }
    
    func exportConfigFile() {
        //读取example文件，删掉configs里面的配置，再用NSDictionary填充到configs里面
        let fileManager = FileManager.default
        
        let filePath:String = Bundle.main.path(forResource: "example-gui-config", ofType: "json")!
        let data = fileManager.contents(atPath: filePath)
        let readString = NSString(data: data!, encoding: String.Encoding.utf8.rawValue)!
        let readStringData = readString.data(using: String.Encoding.utf8.rawValue)
        let jsonArr1 = try! JSONSerialization.jsonObject(with: readStringData!, options: JSONSerialization.ReadingOptions.mutableContainers) as! NSDictionary
        
        let configsArray:NSMutableArray = [] //not using var?
        
        for profile in profiles{
            let configProfile:NSMutableDictionary = [:] //not using var?
            //standard ss profile
            configProfile.setValue(true, forKey: "enable")
            configProfile.setValue(profile.serverHost, forKey: "server")
            configProfile.setValue(NSNumber(value: profile.serverPort as UInt16), forKey: "server_port")//not work
            configProfile.setValue(profile.password, forKey: "password")
            configProfile.setValue(profile.method, forKey: "method")
            configProfile.setValue(profile.remark, forKey: "remarks")
            configProfile.setValue(profile.remark.data(using: String.Encoding.utf8)?.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0)), forKey: "remarks_base64")
            //ssr
            if  profile.ssrObfs != "" {
                configProfile.setValue(profile.ssrObfs, forKey: "obfs")
                configProfile.setValue(profile.ssrProtocol, forKey: "protocol")
                if profile.ssrObfsParam != "" {
                    configProfile.setValue(profile.ssrObfsParam, forKey: "obfsparam")
                }
                if profile.ssrProtocolParam != "" {
                    configProfile.setValue(profile.ssrProtocolParam, forKey: "protocolparam")
                }
            }
            if profile.ssrGroup != "" {
                configProfile.setValue(profile.ssrGroup, forKey: "group")
            }
            configsArray.add(configProfile)
        }
        jsonArr1.setValue(configsArray, forKey: "configs")
        let jsonData = try! JSONSerialization.data(withJSONObject: jsonArr1, options: JSONSerialization.WritingOptions.prettyPrinted)
        let jsonString = NSString(data: jsonData, encoding: String.Encoding.utf8.rawValue)! as String
        let savePanel = NSSavePanel()
        savePanel.title = "Export Config Json File".localized
        savePanel.canCreateDirectories = true
        savePanel.allowedFileTypes = ["json"]
        savePanel.nameFieldStringValue = "export.json"
        savePanel.becomeKey()
        savePanel.begin { (result) -> Void in
            if (result == NSFileHandlingPanelOKButton && (savePanel.url) != nil) {
                //write jsonArr1 back to file
                try! jsonString.write(toFile: (savePanel.url?.path)!, atomically: true, encoding: String.Encoding.utf8)
                NSWorkspace.shared().selectFile((savePanel.url?.path)!, inFileViewerRootedAtPath: (savePanel.directoryURL?.path)!)
                let notification = NSUserNotification()
                notification.title = "Export Server Profile succeed!".localized
                notification.informativeText = "Successful Export \(self.profiles.count) items".localized
                NSUserNotificationCenter.default
                    .deliver(notification)
            }
        }
    }
    
    class func showExampleConfigFile() {
        //copy file to ~/Downloads folder
        let filePath:String = Bundle.main.path(forResource: "example-gui-config", ofType: "json")!
        let fileMgr = FileManager.default
        let dataPath = NSHomeDirectory() + "/Downloads"
        let destPath = dataPath + "/example-gui-config.json"
        //检测文件是否已经存在，如果存在直接用sharedWorkspace显示
        if fileMgr.fileExists(atPath: destPath) {
            NSWorkspace.shared().selectFile(destPath, inFileViewerRootedAtPath: dataPath)
        }else{
            try! fileMgr.copyItem(atPath: filePath, toPath: destPath)
            NSWorkspace.shared().selectFile(destPath, inFileViewerRootedAtPath: dataPath)
        }
    }
}
