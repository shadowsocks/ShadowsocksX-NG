//
//  ImportWindowController.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 2019/9/10.
//  Copyright © 2019 qiuyuzhou. All rights reserved.
//

import Cocoa

class ImportWindowController: NSWindowController {
    @IBOutlet weak var inputBox: NSTextField!
    
    override func windowDidLoad() {
        super.windowDidLoad()

        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
        
        let pb = NSPasteboard.general
        if #available(OSX 10.13, *) {
            if let text = pb.string(forType: NSPasteboard.PasteboardType.URL) {
                if let url = URL(string: text) {
                    if url.scheme == "ss" {
                        inputBox.stringValue = text
                    }
                }
            }
        }
        if let text = pb.string(forType: NSPasteboard.PasteboardType.string) {
            let urls = ServerProfileManager.findURLSInText(text)
            if urls.count > 0 {
                inputBox.stringValue = text
            }
        }
    }
    
    @IBAction func handleImport(_ sender: NSButton) {
        let mgr = ServerProfileManager.instance
        let urls = ServerProfileManager.findURLSInText(inputBox.stringValue)
        let addCount = mgr.addServerProfileByURL(urls: urls)

        if addCount > 0 {
            let alert = NSAlert.init()
            alert.alertStyle = .informational;
            alert.messageText = "Success to add \(addCount) server.".localized
            alert.addButton(withTitle: "OK")
            alert.runModal()
            self.close()
        } else {
            let alert = NSAlert.init()
            alert.alertStyle = .informational;
            alert.messageText = "Not found valid shadowsocks server urls.".localized
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
