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
    @IBOutlet weak var kcptunProfileBox: NSBox!
    
    @IBOutlet weak var hostTextField: NSTextField!
    @IBOutlet weak var portTextField: NSTextField!
    @IBOutlet weak var kcptunPortTextField: NSTextField!
    @IBOutlet weak var methodTextField: NSComboBox!
    
    @IBOutlet weak var passwordTextField: NSTextField!
    @IBOutlet weak var remarkTextField: NSTextField!
    
    @IBOutlet weak var otaCheckBoxBtn: NSButton!
    
    @IBOutlet weak var kcptunCheckBoxBtn: NSButton!
    @IBOutlet weak var kcptunCryptComboBox: NSComboBox!
    @IBOutlet weak var kcptunKeyTextField: NSTextField!
    @IBOutlet weak var kcptunModeComboBox: NSComboBox!
    @IBOutlet weak var kcptunNocompCheckBoxBtn: NSButton!
    @IBOutlet weak var kcptunDatashardTextField: NSTextField!
    @IBOutlet weak var kcptunParityshardTextField: NSTextField!
    @IBOutlet weak var kcptunMTUTextField: NSTextField!
    @IBOutlet weak var kcptunArgumentsTextField: NSTextField!
    
    @IBOutlet weak var removeButton: NSButton!
    let tableViewDragType: String = "ss.server.profile.data"
    
    var defaults: UserDefaults!
    var profileMgr: ServerProfileManager!
    
    var editingProfile: ServerProfile!
    
    var enabledKcptunSubDisosable: Disposable?


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
            "salsa20",
            "chacha20",
            "chacha20-ietf",
            "rc4-md5",
            ])
        
        kcptunCryptComboBox.addItems(withObjectValues: [
            "none",
            "aes",
            "aes-128",
            "aes-192",
            "salsa20",
            "blowfish",
            "twofish",
            "cast5",
            "3des",
            "tea",
            "xtea",
            "xor",
            ])
        
        kcptunModeComboBox.addItems(withObjectValues: [
            "default",
            "normal",
            "fast",
            "fast2",
            "fast3",
            ])
        
        profilesTableView.reloadData()
        updateProfileBoxVisible()
    }
    
    override func awakeFromNib() {
        profilesTableView.register(forDraggedTypes: [tableViewDragType])
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
        profilesTableView.insertRows(at: index, withAnimation: .effectFade)
        
        self.profilesTableView.scrollRowToVisible(self.profileMgr.profiles.count-1)
        self.profilesTableView.selectRowIndexes(index, byExtendingSelection: false)
        profilesTableView.endUpdates()
        updateProfileBoxVisible()
    }
    
    @IBAction func removeProfile(_ sender: NSButton) {
        let index = profilesTableView.selectedRow
        if index >= 0 {
            profilesTableView.beginUpdates()
            profileMgr.profiles.remove(at: index)
            profilesTableView.removeRows(at: IndexSet(integer: index), withAnimation: .effectFade)
            profilesTableView.endUpdates()
        }
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
        window?.performClose(self)
    }
    
    @IBAction func duplicate(_ sender: Any) {
        let profile = profileMgr.profiles[profilesTableView.clickedRow]
        let duplicateProfile = profile.copy() as! ServerProfile
        duplicateProfile.uuid = UUID().uuidString
        profileMgr.profiles.insert(duplicateProfile, at: profilesTableView.clickedRow+1)
        profilesTableView.beginUpdates()
        let index = IndexSet(integer: profileMgr.profiles.count-1)
        profilesTableView.insertRows(at: index, withAnimation: .effectFade)
        self.profilesTableView.scrollRowToVisible(profilesTableView.clickedRow+1)
        self.profilesTableView.selectRowIndexes(index, byExtendingSelection: false)
        profilesTableView.endUpdates()
        updateProfileBoxVisible()
    }
    
    @IBAction func copyCurrentProfileURL2Pasteboard(_ sender: NSButton) {
        let index = profilesTableView.selectedRow
        if  index >= 0 {
            let profile = profileMgr.profiles[index]
            let ssURL = profile.URL()
            if let url = ssURL {
                // Then copy url to pasteboard
                // TODO Why it not working?? It's ok in objective-c
                let pboard = NSPasteboard.general()
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
        if let dis = enabledKcptunSubDisosable {
            dis.dispose()
            enabledKcptunSubDisosable = Optional.none
        }
        if index >= 0 && index < profileMgr.profiles.count {
            editingProfile = profileMgr.profiles[index]
            
            
            enabledKcptunSubDisosable = editingProfile.rx.observeWeakly(Bool.self, "enabledKcptun")
                .subscribe(onNext: { v in
                    if let enabled = v {
                        self.portTextField.isEnabled = !enabled
                    }
            })
            
            hostTextField.bind("value", to: editingProfile, withKeyPath: "serverHost"
                , options: [NSContinuouslyUpdatesValueBindingOption: true])
            portTextField.bind("value", to: editingProfile, withKeyPath: "serverPort"
                , options: [NSContinuouslyUpdatesValueBindingOption: true])
            
            methodTextField.bind("value", to: editingProfile, withKeyPath: "method"
                , options: [NSContinuouslyUpdatesValueBindingOption: true])
            passwordTextField.bind("value", to: editingProfile, withKeyPath: "password"
                , options: [NSContinuouslyUpdatesValueBindingOption: true])
            
            remarkTextField.bind("value", to: editingProfile, withKeyPath: "remark"
                , options: [NSContinuouslyUpdatesValueBindingOption: true])
            
            otaCheckBoxBtn.bind("value", to: editingProfile, withKeyPath: "ota"
                , options: [NSContinuouslyUpdatesValueBindingOption: true])
            
            // --------------------------------------------------
            // Kcptun
            kcptunCheckBoxBtn.bind("value", to: editingProfile, withKeyPath: "enabledKcptun"
                , options: [NSContinuouslyUpdatesValueBindingOption: true])
            
            kcptunPortTextField.bind("value", to: editingProfile, withKeyPath: "serverPort"
                , options: [NSContinuouslyUpdatesValueBindingOption: true])
            
            kcptunProfileBox.bind("Hidden", to: editingProfile, withKeyPath: "enabledKcptun"
                , options: [NSContinuouslyUpdatesValueBindingOption: false,
                            NSValueTransformerNameBindingOption: NSValueTransformerName.negateBooleanTransformerName])
            
            kcptunNocompCheckBoxBtn.bind("value", to: editingProfile, withKeyPath: "kcptunProfile.nocomp", options: nil)
            
            kcptunModeComboBox.bind("value", to: editingProfile, withKeyPath: "kcptunProfile.mode", options: nil)
            
            kcptunCryptComboBox.bind("value", to: editingProfile, withKeyPath: "kcptunProfile.crypt", options: nil)
            
            kcptunKeyTextField.bind("value", to: editingProfile, withKeyPath: "kcptunProfile.key"
                , options: [NSContinuouslyUpdatesValueBindingOption: true])
            
            kcptunDatashardTextField.bind("value", to: editingProfile, withKeyPath: "kcptunProfile.datashard"
                , options: [NSContinuouslyUpdatesValueBindingOption: true])
            
            kcptunParityshardTextField.bind("value", to: editingProfile, withKeyPath: "kcptunProfile.parityshard"
                , options: [NSContinuouslyUpdatesValueBindingOption: true])
            
            kcptunMTUTextField.bind("value", to: editingProfile, withKeyPath: "kcptunProfile.mtu"
                , options: [NSContinuouslyUpdatesValueBindingOption: true])
            
            kcptunArgumentsTextField.bind("value", to: editingProfile, withKeyPath: "kcptunProfile.arguments"
                , options: [NSContinuouslyUpdatesValueBindingOption: true])
            
        } else {
            editingProfile = nil
            hostTextField.unbind("value")
            portTextField.unbind("value")
            
            methodTextField.unbind("value")
            passwordTextField.unbind("value")
            
            remarkTextField.unbind("value")
            
            otaCheckBoxBtn.unbind("value")
            
            kcptunCheckBoxBtn.unbind("value")
        }
    }
    
    func getDataAtRow(_ index:Int) -> (String, Bool) {
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
    
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: tableViewDragType)
        return item
    }
    
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int
        , proposedDropOperation dropOperation: NSTableViewDropOperation) -> NSDragOperation {
        if dropOperation == .above {
            return .move
        }
        return NSDragOperation()
    }
    
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo
        , row: Int, dropOperation: NSTableViewDropOperation) -> Bool {
        if let mgr = profileMgr {
            var oldIndexes = [Int]()
            info.enumerateDraggingItems(options: [], for: tableView, classes: [NSPasteboardItem.self], searchOptions: [:]) {
                if let str = ($0.0.item as! NSPasteboardItem).string(forType: self.tableViewDragType), let index = Int(str) {
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
