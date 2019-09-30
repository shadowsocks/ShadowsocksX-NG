//
//  UserRulesController.swift
//  ShadowsocksX-NG
//
//  Created by 周斌佳 on 16/8/1.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Cocoa

class UserRulesController: NSWindowController {

    @IBOutlet var userRulesView: NSTextView!

    override func windowDidLoad() {
        super.windowDidLoad()

        let fileMgr = FileManager.default
        if !fileMgr.fileExists(atPath: PACUserRuleFilePath) {
            let src = Bundle.main.path(forResource: "user-rule", ofType: "txt")
            try! fileMgr.copyItem(atPath: src!, toPath: PACUserRuleFilePath)
        }

        let str = try? String(contentsOfFile: PACUserRuleFilePath, encoding: String.Encoding.utf8)
        userRulesView.string = str!
    }
    
    @IBAction func didCancel(_ sender: AnyObject) {
        window?.performClose(self)
    }

    @IBAction func didOK(_ sender: AnyObject) {
        if let str = userRulesView?.string {
            do {
                try str.data(using: String.Encoding.utf8)?.write(to: URL(fileURLWithPath: PACUserRuleFilePath), options: .atomic)

                if GeneratePACFile() {
                    // Popup a user notification
                    let notification = NSUserNotification()
                    notification.title = "PAC has been updated by User Rules.".localized
                    NSUserNotificationCenter.default
                        .deliver(notification)
                } else {
                    let notification = NSUserNotification()
                    notification.title = "It's failed to update PAC by User Rules.".localized
                    NSUserNotificationCenter.default
                        .deliver(notification)
                }
            } catch {}
        }
        window?.performClose(self)
    }
}
