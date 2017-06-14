//
//  SubscribePreferenceWindowController.swift
//  ShadowsocksX-NG
//
//  Created by 秦宇航 on 2017/6/15.
//  Copyright © 2017年 qiuyuzhou. All rights reserved.
//

import Cocoa

class SubscribePreferenceWindowController: NSWindowController {

    @IBOutlet weak var FeedLabel: NSTextField!
    @IBOutlet weak var OKButton: NSButton!
    @IBOutlet weak var FeedTextField: NSTextField!
    override func windowDidLoad() {
        super.windowDidLoad()

        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    }
    
    @IBAction func onOk(_ sender: NSButton) {
        print(FeedTextField.stringValue)
        window?.performClose(self)
    }
    
}
