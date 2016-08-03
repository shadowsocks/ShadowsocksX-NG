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

        let fileMgr = NSFileManager.defaultManager()
        if !fileMgr.fileExistsAtPath(PACUserRuleFilePath) {
            let src = NSBundle.mainBundle().pathForResource("user-rule", ofType: "txt")
            try! fileMgr.copyItemAtPath(src!, toPath: PACUserRuleFilePath)
        }

        let str = try? String(contentsOfFile: PACUserRuleFilePath, encoding: NSUTF8StringEncoding)
        userRulesView.string = str
    }
    
    @IBAction func didCancel(sender: AnyObject) {
        window?.performClose(self)
    }

    @IBAction func didOK(sender: AnyObject) {
        if let str = userRulesView.string {
            do {
                try str.dataUsingEncoding(NSUTF8StringEncoding)?.writeToFile(PACUserRuleFilePath, options: .DataWritingAtomic)

                if GeneratePACFile() {
                    // Popup a user notification
                    let notification = NSUserNotification()
                    notification.title = "PAC has been updated by User Rules.".localized
                    NSUserNotificationCenter.defaultUserNotificationCenter()
                        .deliverNotification(notification)
                } else {
                    let notification = NSUserNotification()
                    notification.title = "It's failed to update PAC by User Rules.".localized
                    NSUserNotificationCenter.defaultUserNotificationCenter()
                        .deliverNotification(notification)
                }
            } catch {}
        }
        window?.performClose(self)
    }
}
