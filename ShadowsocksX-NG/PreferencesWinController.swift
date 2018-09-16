//
//  PreferencesWinController.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 2017/3/11.
//  Copyright © 2017年 qiuyuzhou. All rights reserved.
//

import Cocoa
import RxCocoa
import RxSwift

class PreferencesWinController: NSWindowController {
    
    @IBOutlet weak var toolbar: NSToolbar!
    @IBOutlet weak var tabView: NSTabView!
    
    override func windowDidLoad() {
        super.windowDidLoad()

        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(rawValue: "general")
    }
    
    @objc func windowWillClose(_ notification: Notification) {
        NotificationCenter.default
            .post(name: NOTIFY_CONF_CHANGED, object: nil)
    }
    
    @IBAction func toolbarAction(sender: NSToolbarItem) {
        tabView.selectTabViewItem(withIdentifier: sender.itemIdentifier)
    }

    @IBAction func resetProxyExceptions(sender: NSButton) {
        let defaults = UserDefaults.standard
        defaults.set("127.0.0.1, localhost, 192.168.0.0/16, 10.0.0.0/8, FE80::/64, ::1, FD00::/8", forKey: "ProxyExceptions")
    }

}
