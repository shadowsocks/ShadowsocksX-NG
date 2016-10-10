//
//  HTTPPreferencesWindowController.swift
//  ShadowsocksX-NG
//
//  Created by 王晨 on 2016/10/7.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Cocoa

class HTTPPreferencesWindowController: NSWindowController, NSWindowDelegate {
    
    override func windowDidLoad() {
        super.windowDidLoad()
        
        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
        self.window?.delegate = self
    }
    
    //------------------------------------------------------------
    // NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default
            .post(name: Notification.Name(rawValue: NOTIFY_HTTP_CONF_CHANGED), object: nil)
    }
    
}
