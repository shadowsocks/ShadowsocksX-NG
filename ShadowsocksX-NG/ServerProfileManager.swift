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
    
    private override init() {
        profiles = [ServerProfile]()
        
        let defaults = NSUserDefaults.standardUserDefaults()
        if let _profiles = defaults.arrayForKey("ServerProfiles") {
            for _profile in _profiles {
                let profile = ServerProfile.fromDictionary(_profile as! [String : AnyObject])
                profiles.append(profile)
            }
        }
        activeProfileId = defaults.stringForKey("ActiveServerProfileId")
    }
    
    func setActiveProfiledId(id: String) {
        activeProfileId = id
        let defaults = NSUserDefaults.standardUserDefaults()
        defaults.setObject(id, forKey: "ActiveServerProfileId")
    }
    
    func save() {
        let defaults = NSUserDefaults.standardUserDefaults()
        var _profiles = [AnyObject]()
        for profile in profiles {
            if profile.isValid() {
                let _profile = profile.toDictionary()
                _profiles.append(_profile)
            }
        }
        defaults.setObject(_profiles, forKey: "ServerProfiles")
        
        if getActiveProfile() == nil {
            activeProfileId = nil
        }
        
        if activeProfileId != nil {
            defaults.setObject(activeProfileId, forKey: "ActiveServerProfileId")
            writeSSLocalConfFile((getActiveProfile()?.toJsonConfig())!)
        } else {
            defaults.removeObjectForKey("ActiveServerProfileId")
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
        openPanel.becomeKeyWindow()
        openPanel.beginWithCompletionHandler { (result) -> Void in
            if (result == NSFileHandlingPanelOKButton && (openPanel.URL) != nil) {
                let fileManager = NSFileManager.defaultManager()
                let filePath:String = (openPanel.URL?.path!)!
                if (fileManager.fileExistsAtPath(filePath) && filePath.hasSuffix("json")) {
                    let data = fileManager.contentsAtPath(filePath)
                    let readString = NSString(data: data!, encoding: NSUTF8StringEncoding)!
                    let readStringData = readString.dataUsingEncoding(NSUTF8StringEncoding)
                    
                    let jsonArr1 = try! NSJSONSerialization.JSONObjectWithData(readStringData!, options: NSJSONReadingOptions.MutableContainers) as! NSDictionary
                    
                    for item in jsonArr1.objectForKey("configs") as! [[String: AnyObject]]{
                        let profile = ServerProfile()
                        profile.serverHost = item["server"] as! String
                        profile.serverPort = UInt16((item["server_port"]?.integerValue)!)
                        profile.method = item["method"] as! String
                        profile.password = item["password"] as! String
                        profile.remark = item["remarks"] as! String
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
                        NSNotificationCenter.defaultCenter().postNotificationName(NOTIFY_SERVER_PROFILES_CHANGED, object: nil)
                    }
                    let configsCount = jsonArr1.objectForKey("configs")?.count
                    let notification = NSUserNotification()
                    notification.title = "Import Server Profile succeed!".localized
                    notification.informativeText = "Successful import \(configsCount!) items".localized
                    NSUserNotificationCenter.defaultUserNotificationCenter()
                        .deliverNotification(notification)
                }else{
                    let notification = NSUserNotification()
                    notification.title = "Import Server Profile failed!".localized
                    notification.informativeText = "Invalid config file!".localized
                    NSUserNotificationCenter.defaultUserNotificationCenter()
                        .deliverNotification(notification)
                    return
                }
            }
        }
    }
    
    func exportConfigFile() {
        //读取example文件，删掉configs里面的配置，再用NSDictionary填充到configs里面
        let fileManager = NSFileManager.defaultManager()
        
        let filePath:String = NSBundle.mainBundle().bundlePath + "/Contents/Resources/example-gui-config.json"
        let data = fileManager.contentsAtPath(filePath)
        let readString = NSString(data: data!, encoding: NSUTF8StringEncoding)!
        let readStringData = readString.dataUsingEncoding(NSUTF8StringEncoding)
        let jsonArr1 = try! NSJSONSerialization.JSONObjectWithData(readStringData!, options: NSJSONReadingOptions.MutableContainers) as! NSDictionary
        
        let configsArray:NSMutableArray = [] //not using var?
        
        for profile in profiles{
            let configProfile:NSMutableDictionary = [:] //not using var?
            //standard ss profile
            configProfile.setValue(true, forKey: "enable")
            configProfile.setValue(profile.serverHost, forKey: "server")
            configProfile.setValue(NSNumber(unsignedShort:profile.serverPort), forKey: "server_port")//not work
            configProfile.setValue(profile.password, forKey: "password")
            configProfile.setValue(profile.method, forKey: "method")
            configProfile.setValue(profile.remark, forKey: "remarks")
            configProfile.setValue(profile.remark.dataUsingEncoding(NSUTF8StringEncoding)?.base64EncodedStringWithOptions(NSDataBase64EncodingOptions(rawValue: 0)), forKey: "remarks_base64")
            //ssr
            if  profile.ssrObfs != "" {
                configProfile.setValue(profile.ssrObfs, forKey: "obfs")
                configProfile.setValue(profile.ssrProtocol, forKey: "protocol")
                if profile.ssrObfsParam != "" {
                    configProfile.setValue(profile.ssrObfsParam, forKey: "obfsparam")
                }
                if profile.ssrProtocolParam != "" {
                    configProfile.setValue(profile.ssrProtocolParam, forKey: "protoclparam")
                }
            }
            configsArray.addObject(configProfile)
        }
        jsonArr1.setValue(configsArray, forKey: "configs")
        let jsonData = try! NSJSONSerialization.dataWithJSONObject(jsonArr1, options: NSJSONWritingOptions.PrettyPrinted)
        let jsonString = NSString(data: jsonData, encoding: NSUTF8StringEncoding)! as String
        let savePanel = NSSavePanel()
        savePanel.title = "Export Config Json File".localized
        savePanel.canCreateDirectories = true
        savePanel.allowedFileTypes = ["json"]
        savePanel.nameFieldStringValue = "export.json"
        savePanel.becomeKeyWindow()
        savePanel.beginWithCompletionHandler { (result) -> Void in
            if (result == NSFileHandlingPanelOKButton && (savePanel.URL) != nil) {
                //write jsonArr1 back to file
                try! jsonString.writeToFile((savePanel.URL?.path)!, atomically: true, encoding: NSUTF8StringEncoding)
                NSWorkspace.sharedWorkspace().selectFile((savePanel.URL?.path)!, inFileViewerRootedAtPath: (savePanel.directoryURL?.path)!)
                let notification = NSUserNotification()
                notification.title = "Export Server Profile succeed!".localized
                notification.informativeText = "Successful Export \(self.profiles.count) items".localized
                NSUserNotificationCenter.defaultUserNotificationCenter()
                    .deliverNotification(notification)
            }
        }
    }
    
    class func showExampleConfigFile() {
        //copy file to ~/Downloads folder
        let filePath:String = NSBundle.mainBundle().bundlePath + "/Contents/Resources/example-gui-config.json"
        let fileMgr = NSFileManager.defaultManager()
        let dataPath = NSHomeDirectory() + "/Downloads"
        let destPath = dataPath + "/example-gui-config.json"
        //检测文件是否已经存在，如果存在直接用sharedWorkspace显示
        if fileMgr.fileExistsAtPath(destPath) {
            NSWorkspace.sharedWorkspace().selectFile(destPath, inFileViewerRootedAtPath: dataPath)
        }else{
            try! fileMgr.copyItemAtPath(filePath, toPath: destPath)
            NSWorkspace.sharedWorkspace().selectFile(destPath, inFileViewerRootedAtPath: dataPath)
        }
    }
}
