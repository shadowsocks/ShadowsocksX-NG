//
//  VersionChecker.swift
//  ShadowsocksX-NG
//
//  Created by 秦宇航 on 2017/1/9.
//  Copyright © 2017年 qinyuhang. All rights reserved.
//

import Foundation

let _VERSION_XML_URL = "https://raw.githubusercontent.com/shadowsocksr/ShadowsocksX-NG/develop/ShadowsocksX-NG/Info.plist"
let _VERSION_XML_LOCAL:String = Bundle.main.bundlePath + "/Contents/Info.plist"

class VersionChecker: NSObject {
    var haveNewVersion: Bool = false
    enum versionError: Error {
        case CanNotGetOnlineData
    }
    func saveFile(fromURL: String, toPath: String, withName: String) -> Bool {
        let manager = FileManager.default
        let url = URL(string:fromURL)!
        do {
            let st = try String(contentsOf: url, encoding: String.Encoding.utf8)
            print(st)
            let data = st.data(using: String.Encoding.utf8)
            manager.createFile( atPath: toPath + withName , contents: data, attributes: nil)
            return true
            
        } catch {
            print(error)
            return false
        }
    }
    func checkNewVersion(showAlert: Bool) -> Bool {
        
        func getOnlineData() throws -> NSDictionary{
            guard NSDictionary(contentsOf: URL(string:_VERSION_XML_URL)!) != nil else {
                throw versionError.CanNotGetOnlineData
            }
            return NSDictionary(contentsOf: URL(string:_VERSION_XML_URL)!)!
        }
        
        func showAlertView(Title: String, SubTitle: String, ConfirmBtn: String, CancelBtn: String) -> Int {
            let alertView = NSAlert()
            alertView.messageText = Title
            alertView.informativeText = SubTitle
            alertView.addButton(withTitle: ConfirmBtn)
            if CancelBtn != "" {
                alertView.addButton(withTitle: CancelBtn)
            }
            let action = alertView.runModal()
            return action
        }
        
        var localData: NSDictionary = NSDictionary()
        var onlineData: NSDictionary = NSDictionary()
        
        localData = NSDictionary(contentsOfFile: _VERSION_XML_LOCAL)!
        do{
            try onlineData = getOnlineData()
        }catch{
            _ = showAlertView(Title: "网络错误", SubTitle: "由于网络错误无法检查更新", ConfirmBtn: "确认", CancelBtn: "")
            return false
        }
        if (onlineData["CFBundleShortVersionString"] as! String == localData["CFBundleShortVersionString"] as! String && onlineData["CFBundleVersion"] as! String == localData["CFBundleVersion"] as! String){
            if showAlert {
                let currentVersionString:String = localData["CFBundleShortVersionString"] as! String
                let currentBuildString:String = localData["CFBundleVersion"] as! String
                _ = showAlertView(Title: "已是最新版本！", SubTitle: "当前版本 " + currentVersionString + " build " + currentBuildString, ConfirmBtn: "确认", CancelBtn: "")
            }
            return false
        }
        else{
            haveNewVersion = true
            // 弹窗提示有软件更新
            let versionString:String = onlineData["CFBundleShortVersionString"] as! String
            let buildString:String = onlineData["CFBundleVersion"] as! String
            let currentVersionString:String = localData["CFBundleShortVersionString"] as! String
            let currentBuildString:String = localData["CFBundleVersion"] as! String
            let action = showAlertView(Title: "软件有更新！", SubTitle: "新版本为 " + versionString + " build " + buildString + "\n" + "当前版本 " + currentVersionString + " build " + currentBuildString, ConfirmBtn: "前往下载", CancelBtn: "取消")
            switch action {
                case 1000:
                    // go to download
                    NSWorkspace.shared().open(URL(string: "https://github.com/shadowsocksr/ShadowsocksX-NG/releases")!)
                    break
                case 1001:
                    // cancel
                    break
                default:
                    break
            }
            return true
        }
    }
}
