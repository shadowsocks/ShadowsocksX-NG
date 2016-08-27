//
//  BunchImportUtils.swift
//  ShadowsocksX-NG
//
//  Created by 秦宇航 on 16/8/26.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Foundation
//Todo: function 1 showExampleFile, 调用fileManager 拷贝 json 到Downloads文件夹，然后打开Downloads文件夹

//Function 3 导出json配置文件
func showExampleConfigFile() {
    
}

//importConfigFile, String->void
//调用fileManager，读取json文件，对configs for循环调用 profileManager 生成 profile并保存
func importConfigFile() {
    let openPanel = NSOpenPanel()
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
                        profile.ssrObfsParam = item["obfsparam"] as! String
                        profile.ssrProtocol = item["protocol"] as! String
                        profile.ssrProtocolParam = ""
                    }
                    profileMgr.profiles.append(profile)
                    profileMgr.save()
                    NSNotificationCenter.defaultCenter().postNotificationName(NOTIFY_SERVER_PROFILES_CHANGED, object: nil)
                }
                let notification = NSUserNotification()
                notification.title = "Import Server Profile succeed!".localized
                NSUserNotificationCenter.defaultUserNotificationCenter()
                    .deliverNotification(notification)
            }else{
                let notification = NSUserNotification()
                notification.title = "Import Server Profile failed!".localized
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
    jsonArr1.setValue(nil, forKey: "configs")
    let savePanel = NSSavePanel()
    savePanel.canCreateDirectories = true
    savePanel.beginWithCompletionHandler { (result) -> Void in
        if (result == NSFileHandlingPanelOKButton && (savePanel.URL) != nil) {
        }
    }
}