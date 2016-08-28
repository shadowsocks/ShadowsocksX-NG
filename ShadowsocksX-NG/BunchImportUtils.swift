//
//  BunchImportUtils.swift
//  ShadowsocksX-NG
//
//  Created by 秦宇航 on 16/8/26.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Foundation

var profileMgr: ServerProfileManager!

//Todo: function 1 showExampleFile, 调用fileManager 拷贝 json 到Downloads文件夹，然后打开Downloads文件夹

//拷贝json配置文件到~/Downloads文件夹
func showExampleConfigFile() {
    //copy file to ~/Downloads folder
    let filePath:String = NSBundle.mainBundle().bundlePath + "/Contents/Resources/example-gui-config.json"
    let fileMgr = NSFileManager.defaultManager()
    let dataPath = NSHomeDirectory().stringByAppendingString("/Downloads")
    let destPath = dataPath + "/example-gui-config.json"
    //检测文件是否已经存在，如果存在直接用sharedWorkspace显示
    if fileMgr.fileExistsAtPath(destPath) {
        NSWorkspace.sharedWorkspace().selectFile(destPath, inFileViewerRootedAtPath: dataPath)
    }else{
        try! fileMgr.copyItemAtPath(filePath, toPath: destPath)
        NSWorkspace.sharedWorkspace().selectFile(destPath, inFileViewerRootedAtPath: dataPath)
    }
}

//调用fileManager，读取json文件，对configs for循环调用 profileManager 生成 profile并保存
func importConfigFile() {
    let openPanel = NSOpenPanel()
    openPanel.title = "Choose Config Json File".localized
    openPanel.allowsMultipleSelection = false
    openPanel.canChooseDirectories = false
    openPanel.canCreateDirectories = false
    openPanel.canChooseFiles = true
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
                    var profileMgr: ServerProfileManager!
                    profileMgr = ServerProfileManager.instance
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
                    profileMgr.profiles.append(profile)
                    profileMgr.save()
                    NSNotificationCenter.defaultCenter().postNotificationName(NOTIFY_SERVER_PROFILES_CHANGED, object: nil)
                }
                let configsCount = jsonArr1.objectForKey("configs")?.count
                let notification = NSUserNotification()
                notification.title = "Import Server Profile succeed!".localized
                notification.informativeText = "Successful import \(configsCount) items".localized
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
    profileMgr = ServerProfileManager.instance
    let fileManager = NSFileManager.defaultManager()
    
    let filePath:String = NSBundle.mainBundle().bundlePath + "/Contents/Resources/example-gui-config.json"
    let data = fileManager.contentsAtPath(filePath)
    let readString = NSString(data: data!, encoding: NSUTF8StringEncoding)!
    let readStringData = readString.dataUsingEncoding(NSUTF8StringEncoding)
    let jsonArr1 = try! NSJSONSerialization.JSONObjectWithData(readStringData!, options: NSJSONReadingOptions.MutableContainers) as! NSDictionary
    
    var configsArray:NSMutableArray = []
    
    for profile in profileMgr.profiles{
        var configProfile:NSMutableDictionary = [:]
        //standard ss profile
        configProfile.setValue(1, forKey: "enable")
        configProfile.setValue(profile.serverHost, forKey: "server")
        configProfile.setValue(NSNumber(unsignedShort:profile.serverPort), forKey: "server_port")//not work
        configProfile.setValue(profile.password, forKey: "password")
        configProfile.setValue(profile.method, forKey: "method")
        configProfile.setValue(profile.remark, forKey: "remarks")
        configProfile.setValue(profile.remark.dataUsingEncoding(NSUTF8StringEncoding)?.base64EncodedStringWithOptions(NSDataBase64EncodingOptions(rawValue: 0)), forKey: "remarks_base64")
        //ssr
        if  1 == 1 {
            configProfile.setValue(profile.ssrObfs, forKey: "obfs")
            configProfile.setValue(profile.ssrProtocol, forKey: "protocol")
            if 2 == 2 {
                configProfile.setValue(profile.ssrObfsParam, forKey: "obfsparam")
            }
            if 3 == 3 {
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
    savePanel.beginWithCompletionHandler { (result) -> Void in
        if (result == NSFileHandlingPanelOKButton && (savePanel.URL) != nil) {
            //write jsonArr1 back to file
            try! jsonString.writeToFile((savePanel.URL?.path)!, atomically: true, encoding: NSUTF8StringEncoding)
        }
    }
}
