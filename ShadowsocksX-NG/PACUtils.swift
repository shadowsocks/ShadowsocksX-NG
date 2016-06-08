//
//  PACUtils.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/9.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Foundation
import Alamofire

let PACRulesDirPath = NSHomeDirectory() + "/.ShadowsocksX-NE/"
let PACUserRuleFilePath = PACRulesDirPath + "user-rule.txt"
let PACFilePath = PACRulesDirPath + "gfwlist.js"
let GFWListFilePath = PACRulesDirPath + "gfwlist.txt"


// Because of LocalSocks5.ListenPort may be changed
func SyncPac() {
    let nowSocks5Port = NSUserDefaults.standardUserDefaults().integerForKey("LocalSocks5.ListenPort")
    let oldSocks5Port = NSUserDefaults.standardUserDefaults().integerForKey("LocalSocks5.ListenPort.Old")
    if nowSocks5Port != oldSocks5Port {
        GeneratePACFile()
        NSUserDefaults.standardUserDefaults().setInteger(nowSocks5Port, forKey: "LocalSocks5.ListenPort.Old")
    }
}


func GeneratePACFile() -> Bool {
    let fileMgr = NSFileManager.defaultManager()
    // Maker the dir if rulesDirPath is not exesited.
    if !fileMgr.fileExistsAtPath(PACRulesDirPath) {
        try! fileMgr.createDirectoryAtPath(PACRulesDirPath
            , withIntermediateDirectories: true, attributes: nil)
    }
    
    // If gfwlist.txt is not exsited, copy from bundle
    if !fileMgr.fileExistsAtPath(GFWListFilePath) {
        let src = NSBundle.mainBundle().pathForResource("gfwlist", ofType: "txt")
        try! fileMgr.copyItemAtPath(src!, toPath: GFWListFilePath)
    }
    
    // If gfwlist.txt is not exsited, copy from bundle
    if !fileMgr.fileExistsAtPath(PACUserRuleFilePath) {
        let src = NSBundle.mainBundle().pathForResource("user-rule", ofType: "txt")
        try! fileMgr.copyItemAtPath(src!, toPath: PACUserRuleFilePath)
    }
    
    let socks5Port = NSUserDefaults.standardUserDefaults().integerForKey("LocalSocks5.ListenPort")
    
    do {
        let gfwlist = try String(contentsOfFile: GFWListFilePath, encoding: NSUTF8StringEncoding)
        if let data = NSData(base64EncodedString: gfwlist, options: .IgnoreUnknownCharacters) {
            let str = String(data: data, encoding: NSUTF8StringEncoding)
            var lines = str!.componentsSeparatedByCharactersInSet(NSCharacterSet.newlineCharacterSet())
            
            do {
                let userRuleStr = try String(contentsOfFile: PACUserRuleFilePath, encoding: NSUTF8StringEncoding)
                let userRuleLines = userRuleStr.componentsSeparatedByCharactersInSet(NSCharacterSet.newlineCharacterSet())
                
                lines += userRuleLines
            } catch {
                NSLog("Not found user-rule.txt")
            }
            
            // Filter empty and comment lines
            lines = lines.filter({ (s: String) -> Bool in
                if s.isEmpty {
                    return true
                }
                let c = s[s.startIndex]
                if c == "!" || c == "[" {
                    return true
                }
                return false
            })
            
            do {
                // rule lines to json array
                let rulesJsonData: NSData
                    = try NSJSONSerialization.dataWithJSONObject(lines, options: .PrettyPrinted)
                let rulesJsonStr = String(data: rulesJsonData, encoding: NSUTF8StringEncoding)
                
                // Get raw pac js
                let jsPath = NSBundle.mainBundle().URLForResource("abp", withExtension: "js")
                let jsData = NSData(contentsOfURL: jsPath!)
                var jsStr = String(data: jsData!, encoding: NSUTF8StringEncoding)
                
                // Replace rules placeholder in pac js
                jsStr = jsStr!.stringByReplacingOccurrencesOfString("__RULES__"
                    , withString: rulesJsonStr!)
                // Replace __SOCKS5PORT__ palcholder in pac js
                let result = jsStr!.stringByReplacingOccurrencesOfString("__SOCKS5PORT__"
                    , withString: "\(socks5Port)")
                
                // Write the pac js to file.
                try result.dataUsingEncoding(NSUTF8StringEncoding)?
                    .writeToFile(PACFilePath, options: .DataWritingAtomic)
                
                return true
            } catch {
                
            }
        }
        
    } catch {
        NSLog("Not found gfwlist.txt")
    }
    return false
}

func UpdatePACFromGFWList() {
    // Maker the dir if rulesDirPath is not exesited.
    if !NSFileManager.defaultManager().fileExistsAtPath(PACRulesDirPath) {
        do {
            try NSFileManager.defaultManager().createDirectoryAtPath(PACRulesDirPath
                , withIntermediateDirectories: true, attributes: nil)
        } catch {
        }
    }
    
    let url = NSUserDefaults.standardUserDefaults().stringForKey("GFWListURL")
    Alamofire.request(.GET, url!)
        .responseString {
            response in
            if response.result.isSuccess {
                if let v = response.result.value {
                    do {
                        try v.writeToFile(GFWListFilePath, atomically: true, encoding: NSUTF8StringEncoding)
                        if GeneratePACFile() {
                            // Popup a user notification
                            let notification = NSUserNotification()
                            notification.title = "PAC has been updated by latest GFW List.".localized
                            NSUserNotificationCenter.defaultUserNotificationCenter()
                                .deliverNotification(notification)
                        }
                    } catch {
                        
                    }
                }
            } else {
                // Popup a user notification
                let notification = NSUserNotification()
                notification.title = "Failed to download latest GFW List.".localized
                NSUserNotificationCenter.defaultUserNotificationCenter()
                    .deliverNotification(notification)
            }
        }
}
