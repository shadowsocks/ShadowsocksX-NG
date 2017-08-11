//
//  UserScriptController.swift
//  ShadowsocksX-NG
//
//  Created by Sanchew on 2017/8/11.
//  Copyright © 2017年 qiuyuzhou. All rights reserved.
//

import Cocoa

class UserScriptController: NSWindowController {

    @IBOutlet var userScriptView: NSTextView!
    
    override func windowDidLoad() {
        super.windowDidLoad()
        
        let fileMgr = FileManager.default
        if !fileMgr.fileExists(atPath: PACUserScriptFilePath) {
            let src = Bundle.main.path(forResource: "user-script", ofType: "txt")
            try! fileMgr.copyItem(atPath: src!, toPath: PACUserScriptFilePath)
        }
        
        let str = try? String(contentsOfFile: PACUserScriptFilePath, encoding: String.Encoding.utf8)
        userScriptView.string = str
    }
    
    @IBAction func didCancel(_ sender: AnyObject) {
        window?.performClose(self)
    }
    
    @IBAction func didOK(_ sender: AnyObject) {
        if let str = userScriptView.string {
            do {
                try str.data(using: String.Encoding.utf8)?.write(to: URL(fileURLWithPath: PACUserScriptFilePath), options: .atomic)
                
                if GeneratePACFile() {
                    // Popup a user notification
                    let notification = NSUserNotification()
                    notification.title = "PAC has been updated by User Script.".localized
                    NSUserNotificationCenter.default
                        .deliver(notification)
                } else {
                    let notification = NSUserNotification()
                    notification.title = "It's failed to update PAC by User Script.".localized
                    NSUserNotificationCenter.default
                        .deliver(notification)
                }
            } catch {}
        }
        window?.performClose(self)
    }
}
