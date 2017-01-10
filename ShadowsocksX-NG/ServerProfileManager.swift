//
//  ServerProfileManager.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/6. Modified by 秦宇航 16/9/12 
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
        if let _profiles = defaults.array(forKey: "ServerProfiles") {
            for _profile in _profiles {
                let profile = ServerProfile.fromDictionary(_profile as! [String : AnyObject])
                profiles.append(profile)
            }
        }
        activeProfileId = defaults.string(forKey: "ActiveServerProfileId")
    }
    
    func setActiveProfiledId(_ id: String) {
        activeProfileId = id
        let defaults = UserDefaults.standard
        defaults.set(id, forKey: "ActiveServerProfileId")
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
            activeProfileId = nil
        }
        
        if activeProfileId != nil {
            defaults.set(activeProfileId, forKey: "ActiveServerProfileId")
            let _ = writeSSLocalConfFile((getActiveProfile()?.toJsonConfig())!)
        } else {
            defaults.removeObject(forKey: "ActiveServerProfileId")
            removeSSLocalConfFile()
        }
    }
    
    func getActiveProfile() -> ServerProfile? {
        if let id = activeProfileId {
            for p in profiles {
                if p.uuid == id {
                    return p
                }
            }
            return nil
        } else {
            return nil
        }
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
