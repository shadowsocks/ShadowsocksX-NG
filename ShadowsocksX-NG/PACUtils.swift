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
    
    let nowSocks5Port = UserDefaults.standard.integer(forKey: "LocalSocks5.ListenPort")
    let oldSocks5Port = UserDefaults.standard.integer(forKey: "LocalSocks5.ListenPort.Old")
    if nowSocks5Port != oldSocks5Port {
        needGenerate = true
        UserDefaults.standard.set(nowSocks5Port, forKey: "LocalSocks5.ListenPort.Old")
    }
    
    let fileMgr = FileManager.default
    if !fileMgr.fileExists(atPath: PACRulesDirPath) {
        needGenerate = true
    }
    
    if !fileMgr.fileExists(atPath: WhiteListDomainPACFilePath) && !fileMgr.fileExists(atPath: WhiteListIPPACFilePath) {
        needGenerate = true
    }
    
    if needGenerate {
        if !GeneratePACFile() {
            NSLog("GeneratePACFile failed!")
        }
    }
}


func GeneratePACFile() -> Bool {
    let fileMgr = FileManager.default
    // Maker the dir if rulesDirPath is not exesited.
    if !fileMgr.fileExists(atPath: PACRulesDirPath) {
        if fileMgr.fileExists(atPath: OldErrorPACRulesDirPath) {
            try! fileMgr.moveItem(atPath: OldErrorPACRulesDirPath, toPath: PACRulesDirPath)
        } else {
            try! fileMgr.createDirectory(atPath: PACRulesDirPath
                , withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    // If gfwlist.txt is not exsited, copy from bundle
    if !fileMgr.fileExists(atPath: GFWListFilePath) {
        let src = Bundle.main.path(forResource: "gfwlist", ofType: "txt")
        try! fileMgr.copyItem(atPath: src!, toPath: GFWListFilePath)
    }
    
    // If user-rule.txt is not exsited, copy from bundle
    if !fileMgr.fileExists(atPath: PACUserRuleFilePath) {
        let src = Bundle.main.path(forResource: "user-rule", ofType: "txt")
        try! fileMgr.copyItem(atPath: src!, toPath: PACUserRuleFilePath)
    }
    
    // If whitelist.pac is not exsited, copy from bundle
    if !fileMgr.fileExists(atPath: WhiteListDomainPACFilePath) {
        let src = Bundle.main.path(forResource: "whitelist", ofType: "pac")
        try! fileMgr.copyItem(atPath: src!, toPath: WhiteListDomainPACFilePath)
    }
    
    // If whitelistip.pac is not exsited, copy from bundle
    if !fileMgr.fileExists(atPath: WhiteListIPPACFilePath) {
        let src = Bundle.main.path(forResource: "whiteiplist", ofType: "pac")
        try! fileMgr.copyItem(atPath: src!, toPath: WhiteListIPPACFilePath)

    }
    
    let socks5Port = UserDefaults.standard.integer(forKey: "LocalSocks5.ListenPort")
    
    do {
        let gfwlist = try String(contentsOfFile: GFWListFilePath, encoding: String.Encoding.utf8)
        if let data = Data(base64Encoded: gfwlist, options: .ignoreUnknownCharacters) {
            let str = String(data: data, encoding: String.Encoding.utf8)
            var lines = str!.components(separatedBy: CharacterSet.newlines)
            
            do {
                let userRuleStr = try String(contentsOfFile: PACUserRuleFilePath, encoding: String.Encoding.utf8)
                let userRuleLines = userRuleStr.components(separatedBy: CharacterSet.newlines)
                
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
                let rulesJsonData: Data
                    = try JSONSerialization.data(withJSONObject: lines, options: .prettyPrinted)
                let rulesJsonStr = String(data: rulesJsonData, encoding: String.Encoding.utf8)
                
                // Get raw pac js
                let jsPath = Bundle.main.url(forResource: "abp", withExtension: "js")
                let jsData = try? Data(contentsOf: jsPath!)
                var jsStr = String(data: jsData!, encoding: String.Encoding.utf8)
                
                // Replace rules placeholder in pac js
                jsStr = jsStr!.replacingOccurrences(of: "__RULES__"
                    , with: rulesJsonStr!)
                // Replace __SOCKS5PORT__ palcholder in pac js
                let result = jsStr!.replacingOccurrences(of: "__SOCKS5PORT__"
                    , with: "\(socks5Port)")
                
                // Write the pac js to file.
                try result.data(using: String.Encoding.utf8)?
                    .write(to: URL(fileURLWithPath: PACFilePath), options: .atomic)
                
                // Setup Pac for White List
                let DomainSrc = Bundle.main.path(forResource: "whitelist", ofType: "pac")
                let IPSrc = Bundle.main.path(forResource: "whiteiplist", ofType: "pac")
                let DomainPacFile = try? Data(contentsOf: URL(fileURLWithPath: DomainSrc!))
                let IPPACFile = try? Data(contentsOf: URL(fileURLWithPath: IPSrc!))
                var DomainPACStr = String(data: DomainPacFile!,encoding: String.Encoding.utf8)!
                var IPPACStr = String(data: IPPACFile!,encoding: String.Encoding.utf8)!
                if(DomainPACStr.range(of: "SOCKS ") == nil) {
                    DomainPACStr = DomainPACStr.replacingOccurrences(of: "SOCKS5 127.0.0.1:1080;", with: "SOCKS5 127.0.0.1:\(socks5Port);SOCKS 127.0.0.1:\(socks5Port);")
                }else{
                    DomainPACStr = DomainPACStr.replacingOccurrences(of: "SOCKS 127.0.0.1:1080;", with: "SOCKS 127.0.0.1:\(socks5Port);")
                    DomainPACStr = DomainPACStr.replacingOccurrences(of: "SOCKS5 127.0.0.1:1080;", with: "SOCKS5 127.0.0.1:\(socks5Port);")
                }
                
                if(IPPACStr.range(of: "SOCKS ") == nil) {
                    IPPACStr = IPPACStr.replacingOccurrences(of: "SOCKS5 127.0.0.1:1080;", with: "SOCKS5 127.0.0.1:\(socks5Port);SOCKS 127.0.0.1:\(socks5Port);")
                }else{
                    IPPACStr = IPPACStr.replacingOccurrences(of: "SOCKS 127.0.0.1:1080;", with: "SOCKS 127.0.0.1:\(socks5Port);")
                    IPPACStr = IPPACStr.replacingOccurrences(of: "SOCKS5 127.0.0.1:1080;", with: "SOCKS5 127.0.0.1:\(socks5Port);")
                }
                
                try
                    DomainPACStr.data(using: String.Encoding.utf8)?.write(to: URL(fileURLWithPath: WhiteListDomainPACFilePath), options: .atomic)
                try
                    IPPACStr.data(using: String.Encoding.utf8)?.write(to: URL(fileURLWithPath: WhiteListIPPACFilePath), options: .atomic)
                
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
    if !FileManager.default.fileExists(atPath: PACRulesDirPath) {
        do {
            try FileManager.default.createDirectory(atPath: PACRulesDirPath
                , withIntermediateDirectories: true, attributes: nil)
        } catch {
        }
    }
    
    let url = UserDefaults.standard.string(forKey: "GFWListURL")
    Alamofire.request(url!)
        .responseString {
            response in
            if response.result.isSuccess {
                if let v = response.result.value {
                    do {
                        try v.write(toFile: GFWListFilePath, atomically: true, encoding: String.Encoding.utf8)
                        if GeneratePACFile() {
                            // Popup a user notification
                            let notification = NSUserNotification()
                            notification.title = "PAC has been updated by latest GFW List.".localized
                            NSUserNotificationCenter.default
                                .deliver(notification)
                        }
                    } catch {
                        
                    }
                }
            } else {
                // Popup a user notification
                let notification = NSUserNotification()
                notification.title = "Failed to download latest GFW List.".localized
                NSUserNotificationCenter.default
                    .deliver(notification)
            }
        }
}

func UpdatePACFromWhiteList(){
    if !FileManager.default.fileExists(atPath: PACRulesDirPath) {
        do {
            try FileManager.default.createDirectory(atPath: PACRulesDirPath
                , withIntermediateDirectories: true, attributes: nil)
        } catch {
        }
    }
    
    let url = UserDefaults.standard.string(forKey: "WhiteListURL")
    Alamofire.request(url!)// request(.GET, url!)
        .responseString {
            response in
            if response.result.isSuccess {
                if let v = response.result.value {
                    do {
                        try v.write(toFile: WhiteListDomainPACFilePath, atomically: true, encoding: String.Encoding.utf8)
                        if GeneratePACFile() {
                            // Popup a user notification
                            let notification = NSUserNotification()
                            notification.title = "White List update succeed.".localized
                            NSUserNotificationCenter.default
                                .deliver(notification)
                        }
                    } catch {
                        
                    }
                }
            } else {
                // Popup a user notification
                let notification = NSUserNotification()
                notification.title = "Failed to download latest White List update succeed.".localized
                NSUserNotificationCenter.default
                    .deliver(notification)
            }
    }
    
    let IPURL = UserDefaults.standard.string(forKey: "WhiteListIPURL")
    Alamofire.request(IPURL!)
        .responseString {
            response in
            if response.result.isSuccess {
                if let v = response.result.value {
                    do {
                        try v.write(toFile:WhiteListIPPACFilePath, atomically: true, encoding: String.Encoding.utf8)
                        if GeneratePACFile() {
                            // Popup a user notification
                            let notification = NSUserNotification()
                            notification.title = "White List update succeed.".localized
                            NSUserNotificationCenter.default
                                .deliver(notification)
                        }
                    } catch {
                        
                    }
                }
            } else {
                // Popup a user notification
                let notification = NSUserNotification()
                notification.title = "Failed to download latest White List update succeed.".localized
                NSUserNotificationCenter.default
                    .deliver(notification)
            }
    }
}
