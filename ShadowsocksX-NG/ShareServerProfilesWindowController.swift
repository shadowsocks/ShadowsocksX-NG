//
//  ShareServerProfilesWindowController.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 2018/9/16.
//  Copyright © 2018年 qiuyuzhou. All rights reserved.
//

import Cocoa

class ShareServerProfilesWindowController: NSWindowController
    , NSTableViewDataSource, NSTableViewDelegate {

    @IBOutlet weak var profilesTableView: NSTableView!
    
    @IBOutlet weak var qrCodeImageView: NSImageView!
    
    @IBOutlet weak var copyAllServerURLsButton: NSButton!
    @IBOutlet weak var saveAllServerURLsAsFileButton: NSButton!
    
    @IBOutlet weak var copyURLButton: NSButton!
    @IBOutlet weak var copyQRCodeButton: NSButton!
    @IBOutlet weak var saveQRCodeAsFileButton: NSButton!
    
    var defaults: UserDefaults!
    var profileMgr: ServerProfileManager!

    override func windowDidLoad() {
        super.windowDidLoad()
        
        defaults = UserDefaults.standard
        profileMgr = ServerProfileManager.instance
        profilesTableView.reloadData()
        
        if !profileMgr.profiles.isEmpty {
            let index = IndexSet(integer: 0)
            profilesTableView.selectRowIndexes(index, byExtendingSelection: false)
        } else {
            copyAllServerURLsButton.isEnabled = false
            saveAllServerURLsAsFileButton.isEnabled = false
            copyURLButton.isEnabled = false
            copyQRCodeButton.isEnabled = false
            saveQRCodeAsFileButton.isEnabled = false
        }
    }
    
    @IBAction func copyURL(_ sender: NSButton) {
        let profile = getSelectedProfile()
        if profile.isValid(), let url = profile.URL() {
            let pb = NSPasteboard.general
            pb.clearContents()
            if pb.writeObjects([url.absoluteString as NSPasteboardWriting]) {
                NSLog("Copy URL to clipboard")
            } else {
                NSLog("Failed to copy URL to clipboard")
            }
        }
    }
    
    @IBAction func copyQRCode(_ sender: NSButton) {
        if let img = qrCodeImageView.image {
            let pb = NSPasteboard.general
            pb.clearContents()
            if pb.writeObjects([img as NSPasteboardWriting]) {
                NSLog("Copy QRCode to clipboard")
            } else {
                NSLog("Failed to copy QRCode to clipboard")
            }
        }
    }
    
    @IBAction func saveQRCodeAsFile(_ sender: NSButton) {
        if let img = qrCodeImageView.image {
            let savePanel = NSSavePanel()
            savePanel.title = "Save QRCode As File".localized
            savePanel.canCreateDirectories = true
            savePanel.allowedFileTypes = ["gif"]
            savePanel.isExtensionHidden = false
            
            let profile = getSelectedProfile()
            if profile.remark.isEmpty {
                savePanel.nameFieldStringValue = "shadowsocks_qrcode.gif"
            } else {
                savePanel.nameFieldStringValue = "shadowsocks_qrcode_\(profile.remark).gif"
            }
            
            savePanel.becomeKey()
            let result = savePanel.runModal()
            if (result.rawValue == NSFileHandlingPanelOKButton && (savePanel.url) != nil) {
                let imgRep = NSBitmapImageRep(data: img.tiffRepresentation!)
                let data = imgRep?.representation(using: NSBitmapImageRep.FileType.gif, properties: [:])
                try! data?.write(to: savePanel.url!)
            }
        }
    }
    
    @IBAction func copyAllServerURLs(_ sender: NSButton) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if pb.writeObjects([getAllServerURLs() as NSPasteboardWriting]) {
            NSLog("Copy all server URLs to clipboard")
        } else {
            NSLog("Failed to all server URLs to clipboard")
        }
    }
    
    @IBAction func saveAllServerURLsAsFile(_ sender: NSButton) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let date_string = formatter.string(from: Date())

        let savePanel = NSSavePanel()
        savePanel.title = "Save All Server URLs To File".localized
        savePanel.canCreateDirectories = true
        savePanel.allowedFileTypes = ["txt"]
        savePanel.isExtensionHidden = false
        savePanel.nameFieldStringValue = "shadowsocks_profiles_\(date_string).txt"
        savePanel.becomeKey()
        let result = savePanel.runModal()
        if (result.rawValue == NSFileHandlingPanelOKButton && (savePanel.url) != nil) {
            let urls = getAllServerURLs()
            try! urls.write(to: (savePanel.url)!, atomically: true, encoding: String.Encoding.utf8)
        }
    }
    
    func getAllServerURLs() -> String {
        let urls = profileMgr.profiles.filter({ (profile) -> Bool in
            return profile.isValid()
        }).map { (profile) -> String in
            return profile.URL()!.absoluteString
        }
        return urls.joined(separator: "\n")
    }
    
    func getSelectedProfile() -> ServerProfile {
        let i = profilesTableView.selectedRow
        return profileMgr.profiles[i]
    }
    
    func getDataAtRow(_ index:Int) -> String {
        let profile = profileMgr.profiles[index]
        if !profile.remark.isEmpty {
            return profile.remark
        } else {
            return profile.serverHost
        }
    }
    
    //--------------------------------------------------
    // For NSTableViewDataSource
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        if let mgr = profileMgr {
            return mgr.profiles.count
        }
        return 0
    }
    
    //--------------------------------------------------
    // For NSTableViewDelegate
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let colId = NSUserInterfaceItemIdentifier(rawValue: "cellTitle")
        if let cell = tableView.makeView(withIdentifier: colId, owner: self) as? NSTableCellView {
            cell.textField?.stringValue = getDataAtRow(row)
            return cell
        }
        return nil
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        if profilesTableView.selectedRow >= 0 {
            let profile = getSelectedProfile()
            if profile.isValid(), let url = profile.URL() {
                let img = createQRImage(url.absoluteString, NSMakeSize(250, 250))
                qrCodeImageView.image = img
                
                copyURLButton.isEnabled = true
                copyQRCodeButton.isEnabled = true
                saveQRCodeAsFileButton.isEnabled = true
                return
            }
        }
        qrCodeImageView.image = nil
            
        copyURLButton.isEnabled = false
        copyQRCodeButton.isEnabled = false
        saveQRCodeAsFileButton.isEnabled = false
    }
}
