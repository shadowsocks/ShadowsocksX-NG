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
    
    @IBOutlet weak var copyURLBtn: NSButton!
    
    var defaults: NSUserDefaults!
    var profileMgr: ServerProfileManager!
    
    var editingProfile: ServerProfile!

    override func windowDidLoad() {
        super.windowDidLoad()

        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
        defaults = NSUserDefaults.standardUserDefaults()
        profileMgr = ServerProfileManager()
        
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
    
    @IBAction func addProfile(sender: NSButton) {
        if editingProfile != nil && !editingProfile.isValid(){
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
    
    func updateProfileBoxVisible() {
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
        } else {
            editingProfile = nil
            hostTextField.unbind("value")
            portTextField.unbind("value")
            
            methodTextField.unbind("value")
            passwordTextField.unbind("value")
            
            remarkTextField.unbind("value")
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
}
