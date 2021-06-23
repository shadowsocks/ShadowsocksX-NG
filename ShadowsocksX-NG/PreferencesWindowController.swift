//
//  PreferencesWindowController.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/6.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Cocoa
import RxCocoa
import RxSwift

class PreferencesWindowController: NSWindowController
    , NSTableViewDataSource, NSTableViewDelegate {
    
    @IBOutlet weak var profilesTableView: NSTableView!
    
    @IBOutlet weak var profileBox: NSBox!
    
    @IBOutlet weak var hostTextField: NSTextField!
    @IBOutlet weak var portTextField: NSTextField!
    @IBOutlet weak var methodTextField: NSComboBox!
    
    @IBOutlet weak var passwordTabView: NSTabView!
    @IBOutlet weak var passwordTextField: NSTextField!
    @IBOutlet weak var passwordSecureTextField: NSSecureTextField!
    @IBOutlet weak var togglePasswordVisibleButton: NSButton!
    @IBOutlet weak var pluginTextField: NSTextField!
    @IBOutlet weak var pluginOptionsTextField: NSTextField!
    @IBOutlet weak var remarkTextField: NSTextField!
    @IBOutlet weak var removeButton: NSButton!
    
    let tableViewDragType: String = "ss.server.profile.data"
    
    var defaults: UserDefaults!
    var profileMgr: ServerProfileManager!
    
    var editingProfile: ServerProfile!


    override func windowDidLoad() {
        super.windowDidLoad()

        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
        
        defaults = UserDefaults.standard
        profileMgr = ServerProfileManager.instance
        
        methodTextField.addItems(withObjectValues: [
            "aes-128-gcm",
            "aes-192-gcm",
            "aes-256-gcm",
            "aes-128-cfb",
            "aes-192-cfb",
            "aes-256-cfb",
            "aes-128-ctr",
            "aes-192-ctr",
            "aes-256-ctr",
            "camellia-128-cfb",
            "camellia-192-cfb",
            "camellia-256-cfb",
            "bf-cfb",
            "chacha20-ietf-poly1305",
            "xchacha20-ietf-poly1305",
            "salsa20",
            "chacha20",
            "chacha20-ietf",
            "rc4-md5",
            ])
        
        profilesTableView.reloadData()
        updateProfileBoxVisible()
    }
    
    override func awakeFromNib() {
        profilesTableView.registerForDraggedTypes([NSPasteboard.PasteboardType(rawValue: tableViewDragType)])
        profilesTableView.allowsMultipleSelection = true
    }
    
    @IBAction func addProfile(_ sender: NSButton) {
        if editingProfile != nil && !editingProfile.isValid(){
            shakeWindows()
            return
        }
        profilesTableView.beginUpdates()
        let profile = ServerProfile()
        profile.remark = "New Server".localized
        profileMgr.profiles.append(profile)
        
        let index = IndexSet(integer: profileMgr.profiles.count-1)
        profilesTableView.insertRows(at: index, withAnimation: NSTableView.AnimationOptions.effectFade)
        
        self.profilesTableView.scrollRowToVisible(self.profileMgr.profiles.count-1)
        self.profilesTableView.selectRowIndexes(index, byExtendingSelection: false)
        profilesTableView.endUpdates()
        updateProfileBoxVisible()
    }
    
    @IBAction func removeProfile(_ sender: NSButton) {
        let index = Int(profilesTableView.selectedRowIndexes.first!)
        var deleteCount = 0
        if index >= 0 {
            profilesTableView.beginUpdates()
            for (_, toDeleteIndex) in profilesTableView.selectedRowIndexes.enumerated() {
                print(profileMgr.profiles.count)
                profileMgr.profiles.remove(at: toDeleteIndex - deleteCount)
                profilesTableView.removeRows(at: IndexSet(integer: toDeleteIndex - deleteCount), withAnimation: NSTableView.AnimationOptions.effectFade)
                deleteCount += 1
            }
            profilesTableView.endUpdates()
        }
        self.profilesTableView.scrollRowToVisible(index-1)
        self.profilesTableView.selectRowIndexes(IndexSet(integer: index-1), byExtendingSelection: false)
        updateProfileBoxVisible()
    }
    
    @IBAction func ok(_ sender: NSButton) {
        if editingProfile != nil {
            if !editingProfile.isValid() {
                // TODO Shake window?
                shakeWindows()
                return
            }
        }
        profileMgr.save()
        window?.performClose(nil)

        NotificationCenter.default
            .post(name: NOTIFY_SERVER_PROFILES_CHANGED, object: nil)
    }
    
    @IBAction func cancel(_ sender: NSButton) {
        profileMgr.reload()
        window?.performClose(self)
    }
    
    @IBAction func duplicate(_ sender: Any) {
        var copyCount = 0
        for (_, toDuplicateIndex) in profilesTableView.selectedRowIndexes.enumerated() {
            print(profileMgr.profiles.count)
            let profile = profileMgr.profiles[toDuplicateIndex + copyCount]
            let duplicateProfile = profile.copy() as! ServerProfile
            duplicateProfile.uuid = UUID().uuidString
            profileMgr.profiles.insert(duplicateProfile, at:toDuplicateIndex + copyCount)
            
            profilesTableView.beginUpdates()
            let index = IndexSet(integer: toDuplicateIndex + copyCount)
            profilesTableView.insertRows(at: index, withAnimation: NSTableView.AnimationOptions.effectFade)
            self.profilesTableView.scrollRowToVisible(toDuplicateIndex + copyCount)
            self.profilesTableView.selectRowIndexes(index, byExtendingSelection: false)
            profilesTableView.endUpdates()
            
            copyCount += 1
        }
        updateProfileBoxVisible()
    }
    
    @IBAction func togglePasswordVisible(_ sender: Any) {
        if passwordTabView.selectedTabViewItem?.identifier as! String == "secure" {
            passwordTabView.selectTabViewItem(withIdentifier: "insecure")
            togglePasswordVisibleButton.image = NSImage(named: "icons8-Eye Filled-50")
        } else {
            passwordTabView.selectTabViewItem(withIdentifier: "secure")
            togglePasswordVisibleButton.image = NSImage(named: "icons8-Blind Filled-50")
        }
    }
    
    @IBAction func openPluginHelp(_ sender: Any) {
        let url = URL(string: "https://github.com/shadowsocks/ShadowsocksX-NG/wiki/SIP003-Plugin")
        NSWorkspace.shared.open(url!)
    }
    
    @IBAction func openPluginFolder(_ sender: Any) {
        let folderPath = NSHomeDirectory() + APP_SUPPORT_DIR + "plugins/"
        let url = URL(fileURLWithPath: folderPath, isDirectory: true)
        NSWorkspace.shared.open(url)
    }
    
    @IBAction func copyCurrentProfileURL2Pasteboard(_ sender: NSButton) {
        let index = profilesTableView.selectedRow
        if  index >= 0 {
            let profile = profileMgr.profiles[index]
            let ssURL = profile.URL()
            if let url = ssURL {
                // Then copy url to pasteboard
                // TODO Why it not working?? It's ok in objective-c
                let pboard = NSPasteboard.general
                pboard.clearContents()
                let rs = pboard.writeObjects([url as NSPasteboardWriting])
                if rs {
                    NSLog("copy to pasteboard success")
                } else {
                    NSLog("copy to pasteboard failed")
                }
            }
        }
    }
    
    func updateProfileBoxVisible() {
        if profileMgr.profiles.count <= 0 {
            removeButton.isEnabled = false
        }else{
            removeButton.isEnabled = true
        }

        if profileMgr.profiles.isEmpty {
            profileBox.isHidden = true
        } else {
            profileBox.isHidden = false
        }
    }
    
    func bindProfile(_ index:Int) {
        NSLog("bind profile \(index)")

        if index >= 0 && index < profileMgr.profiles.count {
            let editingProfile = profileMgr.profiles[index]
            
            hostTextField.bind(NSBindingName(rawValue: "value"), to: editingProfile, withKeyPath: "serverHost"
                , options: [NSBindingOption.continuouslyUpdatesValue: true])
            portTextField.bind(NSBindingName(rawValue: "value"), to: editingProfile, withKeyPath: "serverPort"
                , options: [NSBindingOption.continuouslyUpdatesValue: true])
            
            methodTextField.bind(NSBindingName(rawValue: "value"), to: editingProfile, withKeyPath: "method"
                , options: [NSBindingOption.continuouslyUpdatesValue: true])
            passwordTextField.bind(NSBindingName(rawValue: "value"), to: editingProfile, withKeyPath: "password"
                , options: [NSBindingOption.continuouslyUpdatesValue: true])
            passwordSecureTextField.bind(NSBindingName(rawValue: "value"), to: editingProfile, withKeyPath: "password"
                , options: [NSBindingOption.continuouslyUpdatesValue: true])

            pluginTextField.bind(NSBindingName(rawValue: "value"), to: editingProfile, withKeyPath: "plugin"
                , options: [NSBindingOption.continuouslyUpdatesValue: true])
            pluginOptionsTextField.bind(NSBindingName(rawValue: "value"), to: editingProfile, withKeyPath: "pluginOptions"
                , options: [NSBindingOption.continuouslyUpdatesValue: true])
            
            remarkTextField.bind(NSBindingName(rawValue: "value"), to: editingProfile, withKeyPath: "remark"
                , options: [NSBindingOption.continuouslyUpdatesValue: true])
        } else {
            editingProfile = nil
            hostTextField.unbind(NSBindingName(rawValue: "value"))
            portTextField.unbind(NSBindingName(rawValue: "value"))
            
            methodTextField.unbind(NSBindingName(rawValue: "value"))
            passwordTextField.unbind(NSBindingName(rawValue: "value"))
            
            remarkTextField.unbind(NSBindingName(rawValue: "value"))
        }
    }
    
    func getDataAtRow(_ index:Int) -> (String, Bool) {
        let profile = profileMgr.profiles[index]
        let isActive = (profileMgr.activeProfileId == profile.uuid)
        if !profile.remark.isEmpty {
            return (String(profile.remark.prefix(24)), isActive)
        } else {
            return (profile.serverHost, isActive)
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
    
    func tableView(_ tableView: NSTableView
        , objectValueFor tableColumn: NSTableColumn?
        , row: Int) -> Any? {
        
        let (title, isActive) = getDataAtRow(row)
        
        if tableColumn?.identifier == NSUserInterfaceItemIdentifier("main") {
            return title
        } else if tableColumn?.identifier == NSUserInterfaceItemIdentifier("status") {
            if isActive {
                return NSImage(named: "NSMenuOnStateTemplate")
            } else {
                return nil
            }
        }
        return ""
    }
    
    // Drag & Drop reorder rows
    
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: NSPasteboard.PasteboardType(rawValue: tableViewDragType))
        return item
    }
    
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int
        , proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if dropOperation == .above {
            return .move
        }
        return NSDragOperation()
    }
    
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo
        , row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        if let mgr = profileMgr {
            var oldIndexes = [Int]()
            info.enumerateDraggingItems(options: [], for: tableView, classes: [NSPasteboardItem.self], searchOptions: [:], using: {
                (draggingItem: NSDraggingItem, idx: Int, stop: UnsafeMutablePointer<ObjCBool>) in
                if let str = (draggingItem.item as! NSPasteboardItem).string(forType: NSPasteboard.PasteboardType(rawValue: self.tableViewDragType)), let index = Int(str) {
                    oldIndexes.append(index)
                }
            })
            
            var oldIndexOffset = 0
            var newIndexOffset = 0
            
            // For simplicity, the code below uses `tableView.moveRowAtIndex` to move rows around directly.
            // You may want to move rows in your content array and then call `tableView.reloadData()` instead.
            tableView.beginUpdates()
            for oldIndex in oldIndexes {
                if oldIndex < row {
                    let o = mgr.profiles.remove(at: oldIndex + oldIndexOffset)
                    mgr.profiles.insert(o, at:row - 1)
                    tableView.moveRow(at: oldIndex + oldIndexOffset, to: row - 1)
                    oldIndexOffset -= 1
                } else {
                    let o = mgr.profiles.remove(at: oldIndex)
                    mgr.profiles.insert(o, at:row + newIndexOffset)
                    tableView.moveRow(at: oldIndex, to: row + newIndexOffset)
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
    
    func tableView(_ tableView: NSTableView
        , shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        return false
    }
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
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
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        if profilesTableView.selectedRow >= 0 {
            bindProfile(profilesTableView.selectedRow)
        } else {
            if !profileMgr.profiles.isEmpty {
                let index = IndexSet(integer: profileMgr.profiles.count - 1)
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

        let shakePath = CGMutablePath()
        shakePath.move(to: CGPoint(x:NSMinX(frame), y:NSMinY(frame)))

        for _ in 1...numberOfShakes{
            shakePath.addLine(to: CGPoint(x: NSMinX(frame) - frame.size.width * CGFloat(vigourOfShake), y: NSMinY(frame)))
            shakePath.addLine(to: CGPoint(x: NSMinX(frame) + frame.size.width * CGFloat(vigourOfShake), y: NSMinY(frame)))
        }

        shakePath.closeSubpath()
        shakeAnimation.path = shakePath
        shakeAnimation.duration = CFTimeInterval(durationOfShake)
        window?.animations = ["frameOrigin":shakeAnimation]
        window?.animator().setFrameOrigin(window!.frame.origin)
    }
}
