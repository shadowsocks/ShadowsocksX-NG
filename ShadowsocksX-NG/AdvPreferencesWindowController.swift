//
//  AdvPreferencesWindowController.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/6.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Cocoa

class AdvPreferencesWindowController: NSWindowController, NSWindowDelegate {
    
    override func windowDidLoad() {
        super.windowDidLoad()

        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
        self.window?.delegate = self
    }
    
    //------------------------------------------------------------
    // NSWindowDelegate
    func windowWillClose(notification: NSNotification) {
        NSNotificationCenter.defaultCenter()
            .postNotificationName(NOTIFY_ADV_CONF_CHANGED, object: nil)
    }
    
}
