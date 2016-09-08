//
//  PACUtils.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/9.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Foundation
import Alamofire

let OldErrorPACRulesDirPath = NSHomeDirectory() + "/.ShadowsocksX-NE/"

let PACRulesDirPath = NSHomeDirectory() + "/.ShadowsocksX-NG/"
let PACUserRuleFilePath = PACRulesDirPath + "user-rule.txt"
let PACFilePath = PACRulesDirPath + "gfwlist.js"
let GFWListFilePath = PACRulesDirPath + "gfwlist.txt"
let WhiteListDomainPACFilePath = PACRulesDirPath + "whitelist.pac"
let WhiteListIPPACFilePath = PACRulesDirPath + "whiteiplist.pac"


// Because of LocalSocks5.ListenPort may be changed
func SyncPac() {
    var needGenerate = false
    
    let nowSocks5Port = NSUserDefaults.standardUserDefaults().integerForKey("LocalSocks5.ListenPort")
    let oldSocks5Port = NSUserDefaults.standardUserDefaults().integerForKey("LocalSocks5.ListenPort.Old")
    if nowSocks5Port != oldSocks5Port {
        needGenerate = true
        NSUserDefaults.standardUserDefaults().setInteger(nowSocks5Port, forKey: "LocalSocks5.ListenPort.Old")
    }
    
    let fileMgr = NSFileManager.defaultManager()
    if !fileMgr.fileExistsAtPath(PACRulesDirPath) {
        needGenerate = true
    }
    
    if !fileMgr.fileExistsAtPath(WhiteListDomainPACFilePath) && !fileMgr.fileExistsAtPath(WhiteListIPPACFilePath) {
        needGenerate = true
    }
    
    if needGenerate {
        GeneratePACFile()
    }
}


func GeneratePACFile() -> Bool {
    let fileMgr = NSFileManager.defaultManager()
    // Maker the dir if rulesDirPath is not exesited.
    if !fileMgr.fileExistsAtPath(PACRulesDirPath) {
        if fileMgr.fileExistsAtPath(OldErrorPACRulesDirPath) {
            try! fileMgr.moveItemAtPath(OldErrorPACRulesDirPath, toPath: PACRulesDirPath)
        } else {
            try! fileMgr.createDirectoryAtPath(PACRulesDirPath
                , withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    // If gfwlist.txt is not exsited, copy from bundle
    if !fileMgr.fileExistsAtPath(GFWListFilePath) {
        let src = NSBundle.mainBundle().pathForResource("gfwlist", ofType: "txt")
        try! fileMgr.copyItemAtPath(src!, toPath: GFWListFilePath)
    }
    
    // If user-rule.txt is not exsited, copy from bundle
    if !fileMgr.fileExistsAtPath(PACUserRuleFilePath) {
        let src = NSBundle.mainBundle().pathForResource("user-rule", ofType: "txt")
        try! fileMgr.copyItemAtPath(src!, toPath: PACUserRuleFilePath)
    }
    
    // If whitelist.pac is not exsited, copy from bundle
    if !fileMgr.fileExistsAtPath(WhiteListDomainPACFilePath) {
        let src = NSBundle.mainBundle().pathForResource("whitelist", ofType: "pac")
        try! fileMgr.copyItemAtPath(src!, toPath: WhiteListDomainPACFilePath)
    }
    
    // If whitelistip.pac is not exsited, copy from bundle
    if !fileMgr.fileExistsAtPath(WhiteListIPPACFilePath) {
        let src = NSBundle.mainBundle().pathForResource("whiteiplist", ofType: "pac")
        try! fileMgr.copyItemAtPath(src!, toPath: WhiteListIPPACFilePath)
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
                    return false
                }
                let c = s[s.startIndex]
                if c == "!" || c == "[" {
                    return false
                }
                return true
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
                
                // Setup Pac for White List
                let DomainSrc = NSBundle.mainBundle().pathForResource("whitelist", ofType: "pac")
                let IPSrc = NSBundle.mainBundle().pathForResource("whiteiplist", ofType: "pac")
                let DomainPacFile = NSData(contentsOfFile: DomainSrc!)
                let IPPACFile = NSData(contentsOfFile: IPSrc!)
                var DomainPACStr = String(data: DomainPacFile!,encoding: NSUTF8StringEncoding)!
                var IPPACStr = String(data: IPPACFile!,encoding: NSUTF8StringEncoding)!
                if(DomainPACStr.rangeOfString("SOCKS ") == nil) {
                    DomainPACStr = DomainPACStr.stringByReplacingOccurrencesOfString("SOCKS5 127.0.0.1:1080;", withString: "SOCKS5 127.0.0.1:\(socks5Port);SOCKS 127.0.0.1:\(socks5Port);")
                }else{
                    DomainPACStr = DomainPACStr.stringByReplacingOccurrencesOfString("SOCKS 127.0.0.1:1080;", withString: "SOCKS 127.0.0.1:\(socks5Port);")
                    DomainPACStr = DomainPACStr.stringByReplacingOccurrencesOfString("SOCKS5 127.0.0.1:1080;", withString: "SOCKS5 127.0.0.1:\(socks5Port);")
                }
                
                if(IPPACStr.rangeOfString("SOCKS ") == nil) {
                    IPPACStr = IPPACStr.stringByReplacingOccurrencesOfString("SOCKS5 127.0.0.1:1080;", withString: "SOCKS5 127.0.0.1:\(socks5Port);SOCKS 127.0.0.1:\(socks5Port);")
                }else{
                    IPPACStr = IPPACStr.stringByReplacingOccurrencesOfString("SOCKS 127.0.0.1:1080;", withString: "SOCKS 127.0.0.1:\(socks5Port);")
                    IPPACStr = IPPACStr.stringByReplacingOccurrencesOfString("SOCKS5 127.0.0.1:1080;", withString: "SOCKS5 127.0.0.1:\(socks5Port);")
                }
                
                try
                    DomainPACStr.dataUsingEncoding(NSUTF8StringEncoding)?.writeToFile(WhiteListDomainPACFilePath, options: .DataWritingAtomic)
                try
                    IPPACStr.dataUsingEncoding(NSUTF8StringEncoding)?.writeToFile(WhiteListIPPACFilePath, options: .DataWritingAtomic)
                
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
    // Make the dir if rulesDirPath is not exesited.
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

func UpdatePACFromWhiteList(){
    if !NSFileManager.defaultManager().fileExistsAtPath(PACRulesDirPath) {
        do {
            try NSFileManager.defaultManager().createDirectoryAtPath(PACRulesDirPath
                , withIntermediateDirectories: true, attributes: nil)
        } catch {
        }
    }
    
    let url = NSUserDefaults.standardUserDefaults().stringForKey("WhiteListURL")
    Alamofire.request(.GET, url!)
        .responseString {
            response in
            if response.result.isSuccess {
                if let v = response.result.value {
                    do {
                        try v.writeToFile(WhiteListDomainPACFilePath, atomically: true, encoding: NSUTF8StringEncoding)
                        if GeneratePACFile() {
                            // Popup a user notification
                            let notification = NSUserNotification()
                            notification.title = "White List update succeed.".localized
                            NSUserNotificationCenter.defaultUserNotificationCenter()
                                .deliverNotification(notification)
                        }
                    } catch {
                        
                    }
                }
            } else {
                // Popup a user notification
                let notification = NSUserNotification()
                notification.title = "Failed to download latest White List update succeed.".localized
                NSUserNotificationCenter.defaultUserNotificationCenter()
                    .deliverNotification(notification)
            }
    }
    
    let IPURL = NSUserDefaults.standardUserDefaults().stringForKey("WhiteListIPURL")
    Alamofire.request(.GET, IPURL!)
        .responseString {
            response in
            if response.result.isSuccess {
                if let v = response.result.value {
                    do {
                        try v.writeToFile(WhiteListIPPACFilePath, atomically: true, encoding: NSUTF8StringEncoding)
                        if GeneratePACFile() {
                            // Popup a user notification
                            let notification = NSUserNotification()
                            notification.title = "White List update succeed.".localized
                            NSUserNotificationCenter.defaultUserNotificationCenter()
                                .deliverNotification(notification)
                        }
                    } catch {
                        
                    }
                }
            } else {
                // Popup a user notification
                let notification = NSUserNotification()
                notification.title = "Failed to download latest White List update succeed.".localized
                NSUserNotificationCenter.defaultUserNotificationCenter()
                    .deliverNotification(notification)
            }
    }
}
