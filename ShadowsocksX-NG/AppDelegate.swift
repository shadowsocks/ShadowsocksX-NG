//
//  AppDelegate.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/5.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Cocoa


@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate {
    
    var qrcodeWinCtrl: SWBQRCodeWindowController!
    var preferencesWinCtrl: PreferencesWindowController!
    var advPreferencesWinCtrl: AdvPreferencesWindowController!
    
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var statusMenu: NSMenu!
    
    @IBOutlet weak var runningStatusMenuItem: NSMenuItem!
    @IBOutlet weak var toggleRunningMenuItem: NSMenuItem!
    @IBOutlet weak var autoModeMenuItem: NSMenuItem!
    @IBOutlet weak var globalModeMenuItem: NSMenuItem!
    
    @IBOutlet weak var serversMenuItem: NSMenuItem!
    @IBOutlet var serversPreferencesMenuItem: NSMenuItem!
    
    @IBOutlet weak var lanchAtLoginMenuItem: NSMenuItem!
    
    var statusItem: NSStatusItem!
    
    func applicationDidFinishLaunching(aNotification: NSNotification) {
        // Insert code here to initialize your application
        
        NSUserNotificationCenter.defaultUserNotificationCenter().delegate = self
        
        // Prepare ss-local
        InstallSSLocal()
        
        // Prepare defaults
        let defaults = NSUserDefaults.standardUserDefaults()
        defaults.registerDefaults([
            "ShadowsocksOn": true,
            "LocalSocks5.ListenPort": NSNumber(unsignedShort: 1086),
            "LocalSocks5.ListenAddress": "localhost",
            "LocalSocks5.Timeout": NSNumber(unsignedInteger: 60),
            "LocalSocks5.EnableUDPRelay": NSNumber(bool: false),
            "GFWListURL": "https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt"
        ])
        
        statusItem = NSStatusBar.systemStatusBar().statusItemWithLength(20)
        let image = NSImage(named: "menu_icon")
        image?.template = true
        statusItem.image = image
        statusItem.menu = statusMenu
        
        updateServersMenu()
        
        let notifyCenter = NSNotificationCenter.defaultCenter()
        notifyCenter.addObserverForName(NOTIFY_SERVER_PROFILES_CHANGED, object: nil, queue: nil
            , usingBlock: {
            (note) in
                self.updateServersMenu()
                SyncSSLocal()
            }
        )
        notifyCenter.addObserverForName(NOTIFY_ADV_CONF_CHANGED, object: nil, queue: nil
            , usingBlock: {
            (note) in
                SyncSSLocal()
            }
        )
        notifyCenter.addObserverForName("NOTIFY_FOUND_SS_URL", object: nil, queue: nil) {
            (note: NSNotification) in
            if let userInfo = note.userInfo {
                let urls: [NSURL] = userInfo["urls"] as! [NSURL]
                
                let mgr = ServerProfileManager()
                var isChanged = false
                
                for url in urls {
                    let profielDict = ParseSSURL(url)
                    if let profielDict = profielDict {
                        let profile = ServerProfile.fromDictionary(profielDict)
                        mgr.profiles.append(profile)
                        isChanged = true
                        
                        let userNote = NSUserNotification()
                        userNote.title = "Add Shadowsocks Server Profile".localized
                        userNote.subtitle = "By scan QR Code".localized
                        userNote.informativeText = "Host: \(profile.serverHost)"
                        " Port: \(profile.serverPort)"
                        " Encription Method: \(profile.method)".localized
                        userNote.soundName = NSUserNotificationDefaultSoundName
                        
                        NSUserNotificationCenter.defaultUserNotificationCenter()
                            .deliverNotification(userNote);
                    }
                }
                
                if isChanged {
                    mgr.save()
                    self.updateServersMenu()
                }
            }
        }
        
        updateMainMenu()
        SyncSSLocal()
    }

    func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
    }
    
    @IBAction func toggleRunning(sender: NSMenuItem) {
        let defaults = NSUserDefaults.standardUserDefaults()
        var isOn = defaults.boolForKey("ShadowsocksOn")
        isOn = !isOn
        defaults.setBool(isOn, forKey: "ShadowsocksOn")
        
        updateMainMenu()
        
        if isOn {
            StartSSLocal()
        } else {
            StopSSLocal()
        }
    }

    @IBAction func updateGFWList(sender: NSMenuItem) {
        UpdatePACFromGFWList()
    }
    
    @IBAction func showQRCodeForCurrentServer(sender: NSMenuItem) {
        var errMsg: String?
        let mgr = ServerProfileManager()
        if let profile = mgr.getActiveProfile() {
            if profile.isValid() {
                // Show window
                if qrcodeWinCtrl != nil{
                    qrcodeWinCtrl.close()
                }
                qrcodeWinCtrl = SWBQRCodeWindowController(windowNibName: "SWBQRCodeWindowController")
                qrcodeWinCtrl.qrCode = profile.URL()!.absoluteString
                qrcodeWinCtrl.showWindow(self)
                NSApp.activateIgnoringOtherApps(true)
                qrcodeWinCtrl.window?.makeKeyAndOrderFront(nil)
                
                return
            } else {
                errMsg = "Current server profile is not valid.".localized
            }
        } else {
            errMsg = "No current server profile.".localized
        }
        let userNote = NSUserNotification()
        userNote.title = errMsg
        userNote.soundName = NSUserNotificationDefaultSoundName
        
        NSUserNotificationCenter.defaultUserNotificationCenter()
            .deliverNotification(userNote);
    }
    
    @IBAction func scanQRCodeFromScreen(sender: NSMenuItem) {
        ScanQRCodeOnScreen()
    }

    @IBAction func toggleLaunghAtLogin(sender: NSMenuItem) {
        
    }
    
    @IBAction func selectPACMode(sender: NSMenuItem) {
        
    }
    
    @IBAction func selectGlobalMode(sender: NSMenuItem) {
        
    }
    
    @IBAction func editServerPreferences(sender: NSMenuItem) {
        if preferencesWinCtrl != nil {
            preferencesWinCtrl.close()
        }
        let ctrl = PreferencesWindowController(windowNibName: "PreferencesWindowController")
        preferencesWinCtrl = ctrl
        
        ctrl.showWindow(self)
        NSApp.activateIgnoringOtherApps(true)
        ctrl.window?.makeKeyAndOrderFront(self)
    }
    
    @IBAction func editAdvPreferences(sender: NSMenuItem) {
        if advPreferencesWinCtrl != nil {
            advPreferencesWinCtrl.close()
        }
        let ctrl = AdvPreferencesWindowController(windowNibName: "AdvPreferencesWindowController")
        advPreferencesWinCtrl = ctrl
        
        ctrl.showWindow(self)
        NSApp.activateIgnoringOtherApps(true)
        ctrl.window?.makeKeyAndOrderFront(self)
    }
    
    @IBAction func selectServer(sender: NSMenuItem) {
        let index = sender.tag
        let spMgr = ServerProfileManager()
        let newProfile = spMgr.profiles[index]
        if newProfile.uuid != spMgr.activeProfileId {
            spMgr.setActiveProfiledId(newProfile.uuid)
            updateServersMenu()
            SyncSSLocal()
        }
    }
    
    func updateMainMenu() {
        let defaults = NSUserDefaults.standardUserDefaults()
        let isOn = defaults.boolForKey("ShadowsocksOn")
        if isOn {
            runningStatusMenuItem.title = "Shadowsocks: On".localized
            toggleRunningMenuItem.title = "Close Shadowsocks".localized
        } else {
            runningStatusMenuItem.title = "Shadowsocks: Off".localized
            toggleRunningMenuItem.title = "Open Shadowsocks".localized
        }
        
        
        
    }
    
    func updateServersMenu() {
        let mgr = ServerProfileManager()
        serversMenuItem.submenu?.removeAllItems()
        let preferencesItem = serversPreferencesMenuItem
        
        var i = 0
        for p in mgr.profiles {
            let item = NSMenuItem()
            item.tag = i
            if p.remark.isEmpty {
                item.title = "\(p.serverHost):\(p.serverPort)"
            } else {
                item.title = "\(p.remark) (\(p.serverHost):\(p.serverPort))"
            }
            if mgr.activeProfileId == p.uuid {
                item.state = 1
            }
            if !p.isValid() {
                item.enabled = false
            }
            item.action = #selector(AppDelegate.selectServer)
            
            serversMenuItem.submenu?.addItem(item)
            i += 1
        }
        if !mgr.profiles.isEmpty {
            serversMenuItem.submenu?.addItem(NSMenuItem.separatorItem())
        }
        serversMenuItem.submenu?.addItem(preferencesItem)
    }
    
    //------------------------------------------------------------
    // NSUserNotificationCenterDelegate
    
    func userNotificationCenter(center: NSUserNotificationCenter
        , shouldPresentNotification notification: NSUserNotification) -> Bool {
        return true
    }
}

