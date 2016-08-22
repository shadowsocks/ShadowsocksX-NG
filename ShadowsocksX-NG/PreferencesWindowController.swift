//
//  PreferencesWindowController.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/6.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Cocoa

class PreferencesWindowController: NSWindowController
    , NSTableViewDataSource, NSTableViewDelegate {
    
    @IBOutlet weak var profilesTableView: NSTableView!
    
    @IBOutlet weak var profileBox: NSBox!
    
    @IBOutlet weak var hostTextField: NSTextField!
    @IBOutlet weak var portTextField: NSTextField!
    @IBOutlet weak var methodTextField: NSComboBox!
    
    @IBOutlet weak var passwordTextField: NSTextField!
    @IBOutlet weak var remarkTextField: NSTextField!
    
    @IBOutlet weak var otaCheckBoxBtn: NSButton!
    
    @IBOutlet weak var copyURLBtn: NSButton!
    
    @IBOutlet weak var removeButton: NSButton!
    let tableViewDragType: String = "ss.server.profile.data"
    
    var defaults: NSUserDefaults!
    var profileMgr: ServerProfileManager!
    
    var editingProfile: ServerProfile!


    override func windowDidLoad() {
        super.windowDidLoad()

        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
        defaults = NSUserDefaults.standardUserDefaults()
        profileMgr = ServerProfileManager.instance
        
        methodTextField.addItemsWithObjectValues([
            "aes-128-cfb",
            "aes-192-cfb",
            "aes-256-cfb",
            "des-cfb",
            "bf-cfb",
            "cast5-cfb",
            "rc4-md5",
            "chacha20",
            "salsa20",
            "rc4",
            "table",
            ])
        
        profilesTableView.reloadData()
        updateProfileBoxVisible()
    }
    
    override func awakeFromNib() {
        profilesTableView.registerForDraggedTypes([tableViewDragType])
    }
    
    @IBAction func addProfile(sender: NSButton) {
        if editingProfile != nil && !editingProfile.isValid(){
            shakeWindows()
            return
        }
        profilesTableView.beginUpdates()
        let profile = ServerProfile()
        profile.remark = "New Server".localized
        profileMgr.profiles.append(profile)
        
        let index = NSIndexSet(index: profileMgr.profiles.count-1)
        profilesTableView.insertRowsAtIndexes(index, withAnimation: .EffectFade)
        
        self.profilesTableView.scrollRowToVisible(self.profileMgr.profiles.count-1)
        self.profilesTableView.selectRowIndexes(index, byExtendingSelection: false)
        profilesTableView.endUpdates()
        updateProfileBoxVisible()
    }
    
    @IBAction func removeProfile(sender: NSButton) {
        let index = profilesTableView.selectedRow
        if index >= 0 {
            profilesTableView.beginUpdates()
            profileMgr.profiles.removeAtIndex(index)
            profilesTableView.removeRowsAtIndexes(NSIndexSet(index: index), withAnimation: .EffectFade)
            profilesTableView.endUpdates()
        }
        updateProfileBoxVisible()
    }
    
    @IBAction func ok(sender: NSButton) {
        if editingProfile != nil {
            if !editingProfile.isValid() {
                // TODO Shake window?
                shakeWindows()
                return
            }
        }
        profileMgr.save()
        window?.performClose(nil)

        
        NSNotificationCenter.defaultCenter()
            .postNotificationName(NOTIFY_SERVER_PROFILES_CHANGED, object: nil)
    }
    
    @IBAction func cancel(sender: NSButton) {
        window?.performClose(self)
    }
    
    @IBAction func copyCurrentProfileURL2Pasteboard(sender: NSButton) {
        let index = profilesTableView.selectedRow
        if  index >= 0 {
            let profile = profileMgr.profiles[index]
            let ssURL = profile.URL()
            if let url = ssURL {
                // Then copy url to pasteboard
                // TODO Why it not working?? It's ok in objective-c
                let pboard = NSPasteboard.generalPasteboard()
                pboard.clearContents()
                let rs = pboard.writeObjects([url])
                if rs {
                    NSLog("copy to pasteboard success")
                } else {
                    NSLog("copy to pasteboard failed")
                }
            }
        }
    }
    
    func updateProfileBoxVisible() {
        if profileMgr.profiles.count <= 1 {
            removeButton.enabled = false
        }else{
            removeButton.enabled = true
        }

        if profileMgr.profiles.isEmpty {
            profileBox.hidden = true
        } else {
            profileBox.hidden = false
        }
    }
    
    func bindProfile(index:Int) {
        NSLog("bind profile \(index)")
        if index >= 0 && index < profileMgr.profiles.count {
            editingProfile = profileMgr.profiles[index]
            
            hostTextField.bind("value", toObject: editingProfile, withKeyPath: "serverHost"
                , options: [NSContinuouslyUpdatesValueBindingOption: true])
            portTextField.bind("value", toObject: editingProfile, withKeyPath: "serverPort"
                , options: [NSContinuouslyUpdatesValueBindingOption: true])
            
            methodTextField.bind("value", toObject: editingProfile, withKeyPath: "method"
                , options: [NSContinuouslyUpdatesValueBindingOption: true])
            passwordTextField.bind("value", toObject: editingProfile, withKeyPath: "password"
                , options: [NSContinuouslyUpdatesValueBindingOption: true])
            
            remarkTextField.bind("value", toObject: editingProfile, withKeyPath: "remark"
                , options: [NSContinuouslyUpdatesValueBindingOption: true])
            
            otaCheckBoxBtn.bind("value", toObject: editingProfile, withKeyPath: "ota"
                , options: [NSContinuouslyUpdatesValueBindingOption: true])
        } else {
            editingProfile = nil
            hostTextField.unbind("value")
            portTextField.unbind("value")
            
            methodTextField.unbind("value")
            passwordTextField.unbind("value")
            
            remarkTextField.unbind("value")
            
            otaCheckBoxBtn.unbind("value")
        }
    }
    
    func getDataAtRow(index:Int) -> (String, Bool) {
        let profile = profileMgr.profiles[index]
        let isActive = (profileMgr.activeProfileId == profile.uuid)
        if !profile.remark.isEmpty {
            return (profile.remark, isActive)
        } else {
            return (profile.serverHost, isActive)
        }
    }
    
    //--------------------------------------------------
    // For NSTableViewDataSource
    
    func numberOfRowsInTableView(tableView: NSTableView) -> Int {
        if let mgr = profileMgr {
            return mgr.profiles.count
        }
        return 0
    }
    
    func tableView(tableView: NSTableView
        , objectValueForTableColumn tableColumn: NSTableColumn?
        , row: Int) -> AnyObject? {
        
        let (title, isActive) = getDataAtRow(row)
        
        if tableColumn?.identifier == "main" {
            return title
        } else if tableColumn?.identifier == "status" {
            if isActive {
                return NSImage(named: "NSMenuOnStateTemplate")
            } else {
                return nil
            }
        }
        return ""
    }
    
    // Drag & Drop reorder rows
    
    func tableView(tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: tableViewDragType)
        return item
    }
    
    func tableView(tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int
        , proposedDropOperation dropOperation: NSTableViewDropOperation) -> NSDragOperation {
        if dropOperation == .Above {
            return .Move
        }
        return .None
    }
    
    func tableView(tableView: NSTableView, acceptDrop info: NSDraggingInfo
        , row: Int, dropOperation: NSTableViewDropOperation) -> Bool {
        if let mgr = profileMgr {
            var oldIndexes = [Int]()
            info.enumerateDraggingItemsWithOptions([], forView: tableView, classes: [NSPasteboardItem.self], searchOptions: [:]) {
                if let str = ($0.0.item as! NSPasteboardItem).stringForType(self.tableViewDragType), index = Int(str) {
                    oldIndexes.append(index)
                }
            }
            
            var oldIndexOffset = 0
            var newIndexOffset = 0
            
            // For simplicity, the code below uses `tableView.moveRowAtIndex` to move rows around directly.
            // You may want to move rows in your content array and then call `tableView.reloadData()` instead.
            tableView.beginUpdates()
            for oldIndex in oldIndexes {
                if oldIndex < row {
                    let o = mgr.profiles.removeAtIndex(oldIndex + oldIndexOffset)
                    mgr.profiles.insert(o, atIndex:row - 1)
                    tableView.moveRowAtIndex(oldIndex + oldIndexOffset, toIndex: row - 1)
                    oldIndexOffset -= 1
                } else {
                    let o = mgr.profiles.removeAtIndex(oldIndex)
                    mgr.profiles.insert(o, atIndex:row + newIndexOffset)
                    tableView.moveRowAtIndex(oldIndex, toIndex: row + newIndexOffset)
                    newIndexOffset += 1
                }
            }
            tableView.endUpdates()
        
            return true
        }
        return false
    }
    
    //--------------------------------------------------
    // For NSTableViewDelegate
    
    func tableView(tableView: NSTableView
        , shouldEditTableColumn tableColumn: NSTableColumn?, row: Int) -> Bool {
        return false
    }
    
    func tableView(tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if row < 0 {
            editingProfile = nil
            return true
        }
        if editingProfile != nil {
            if !editingProfile.isValid() {
                return false
            }
        }
        
        return true
    }
    
    func tableViewSelectionDidChange(notification: NSNotification) {
        if profilesTableView.selectedRow >= 0 {
            bindProfile(profilesTableView.selectedRow)
        } else {
            if !profileMgr.profiles.isEmpty {
                let index = NSIndexSet(index: profileMgr.profiles.count - 1)
                profilesTableView.selectRowIndexes(index, byExtendingSelection: false)
            }
        }
    }

    func shakeWindows(){
        let numberOfShakes:Int = 8
        let durationOfShake:Float = 0.5
        let vigourOfShake:Float = 0.05

        let frame:CGRect = (window?.frame)!
        let shakeAnimation = CAKeyframeAnimation()

        let shakePath = CGPathCreateMutable()
        CGPathMoveToPoint(shakePath, nil, NSMinX(frame), NSMinY(frame))

        for _ in 1...numberOfShakes{
            CGPathAddLineToPoint(shakePath, nil, NSMinX(frame) - frame.size.width * CGFloat(vigourOfShake), NSMinY(frame))
            CGPathAddLineToPoint(shakePath, nil, NSMinX(frame) + frame.size.width * CGFloat(vigourOfShake), NSMinY(frame))
        }

        CGPathCloseSubpath(shakePath)
        shakeAnimation.path = shakePath
        shakeAnimation.duration = CFTimeInterval(durationOfShake)
        window?.animations = ["frameOrigin":shakeAnimation]
        window?.animator().setFrameOrigin(window!.frame.origin)
    }
}
