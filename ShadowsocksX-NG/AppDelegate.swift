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
    
    var launchAtLoginController: LaunchAtLoginController = LaunchAtLoginController()
    
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var statusMenu: NSMenu!
    
    @IBOutlet weak var runningStatusMenuItem: NSMenuItem!
    @IBOutlet weak var toggleRunningMenuItem: NSMenuItem!
    @IBOutlet weak var autoModeMenuItem: NSMenuItem!
    @IBOutlet weak var globalModeMenuItem: NSMenuItem!
    @IBOutlet weak var manualModeMenuItem: NSMenuItem!
    
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
            "ShadowsocksRunningMode": "auto",
            "LocalSocks5.ListenPort": NSNumber(unsignedShort: 1086),
            "LocalSocks5.ListenAddress": "127.0.0.1",
            "LocalSocks5.Timeout": NSNumber(unsignedInteger: 60),
            "LocalSocks5.EnableUDPRelay": NSNumber(bool: false),
            "LocalSocks5.EnableVerboseMode": NSNumber(bool: false),
            "GFWListURL": "https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt"
        ])
        
        statusItem = NSStatusBar.systemStatusBar().statusItemWithLength(20)
        let image = NSImage(named: "menu_icon")
        image?.template = true
        statusItem.image = image
        statusItem.menu = statusMenu
        
        
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
                        if userInfo["source"] as! String == "qrcode" {
                            userNote.subtitle = "By scan QR Code".localized
                        } else if userInfo["source"] as! String == "url" {
                            userNote.subtitle = "By Handle SS URL".localized
                        }
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
        
        // Handle ss url scheme
        NSAppleEventManager.sharedAppleEventManager().setEventHandler(self
            , andSelector: #selector(self.handleURLEvent)
            , forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        
        updateMainMenu()
        updateServersMenu()
        updateRunningModeMenu()
        updateLaunchAtLoginMenu()
        
        ProxyConfHelper.install()
        applyConfig()
        SyncSSLocal()
    }

    func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
    }
    
    func applyConfig() {
        let defaults = NSUserDefaults.standardUserDefaults()
        let isOn = defaults.boolForKey("ShadowsocksOn")
        let mode = defaults.stringForKey("ShadowsocksRunningMode")
        
        if isOn {
            StartSSLocal()
            if mode == "auto" {
                ProxyConfHelper.enablePACProxy()
            } else if mode == "global" {
                ProxyConfHelper.enableGlobalProxy()
            } else if mode == "manual" {
                ProxyConfHelper.disableProxy()
            }
        } else {
            StopSSLocal()
            ProxyConfHelper.disableProxy()
        }
    }
    
    @IBAction func toggleRunning(sender: NSMenuItem) {
        let defaults = NSUserDefaults.standardUserDefaults()
        var isOn = defaults.boolForKey("ShadowsocksOn")
        isOn = !isOn
        defaults.setBool(isOn, forKey: "ShadowsocksOn")
        
        updateMainMenu()
        
        applyConfig()
    }

    @IBAction func updateGFWList(sender: NSMenuItem) {
        UpdatePACFromGFWList()
    }
    
    @IBAction func editUserRulesForPAC(sender: NSMenuItem) {
        let url = NSURL(fileURLWithPath: PACUserRuleFilePath)
        NSWorkspace.sharedWorkspace().openURL(url)
    }
    
    @IBAction func applyUserRulesForPAC(sender: NSMenuItem) {
        if GeneratePACFile() {
            // Popup a user notification
            let notification = NSUserNotification()
            notification.title = "PAC has been updated by User Rules.".localized
            NSUserNotificationCenter.defaultUserNotificationCenter()
                .deliverNotification(notification)
        } else {
            let notification = NSUserNotification()
            notification.title = "It's failed to update PAC by User Rules.".localized
            NSUserNotificationCenter.defaultUserNotificationCenter()
                .deliverNotification(notification)
        }
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
        launchAtLoginController.launchAtLogin = !launchAtLoginController.launchAtLogin;
        updateLaunchAtLoginMenu()
    }
    
    @IBAction func selectPACMode(sender: NSMenuItem) {
        let defaults = NSUserDefaults.standardUserDefaults()
        defaults.setValue("auto", forKey: "ShadowsocksRunningMode")
        updateRunningModeMenu()
        applyConfig()
    }
    
    @IBAction func selectGlobalMode(sender: NSMenuItem) {
        let defaults = NSUserDefaults.standardUserDefaults()
        defaults.setValue("global", forKey: "ShadowsocksRunningMode")
        updateRunningModeMenu()
        applyConfig()
    }
    
    @IBAction func selectManualMode(sender: NSMenuItem) {
        let defaults = NSUserDefaults.standardUserDefaults()
        defaults.setValue("manual", forKey: "ShadowsocksRunningMode")
        updateRunningModeMenu()
        applyConfig()
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
    
    @IBAction func showLogs(sender: NSMenuItem) {
        let ws = NSWorkspace.sharedWorkspace()
        if let appUrl = ws.URLForApplicationWithBundleIdentifier("com.apple.Console") {
            try! ws.launchApplicationAtURL(appUrl
                ,options: .Default
                ,configuration: [NSWorkspaceLaunchConfigurationArguments: "~/Library/Logs/ss-local.log"])
        }
    }
    
    @IBAction func feedback(sender: NSMenuItem) {
        NSWorkspace.sharedWorkspace().openURL(NSURL(string: "https://github.com/qiuyuzhou/ShadowsocksX-NG/issues")!)
    }
    
    @IBAction func showAbout(sender: NSMenuItem) {
        NSApp.orderFrontStandardAboutPanel(sender);
        NSApp.activateIgnoringOtherApps(true)
    }
    
    func updateLaunchAtLoginMenu() {
        if launchAtLoginController.launchAtLogin {
            lanchAtLoginMenuItem.state = 1
        } else {
            lanchAtLoginMenuItem.state = 0
        }
    }
    
    func updateRunningModeMenu() {
        let defaults = NSUserDefaults.standardUserDefaults()
        let mode = defaults.stringForKey("ShadowsocksRunningMode")
        if mode == "auto" {
            autoModeMenuItem.state = 1
            globalModeMenuItem.state = 0
            manualModeMenuItem.state = 0
        } else if mode == "global" {
            autoModeMenuItem.state = 0
            globalModeMenuItem.state = 1
            manualModeMenuItem.state = 0
        } else if mode == "manual" {
            autoModeMenuItem.state = 0
            globalModeMenuItem.state = 0
            manualModeMenuItem.state = 1
        }
    }
    
    func updateMainMenu() {
        let defaults = NSUserDefaults.standardUserDefaults()
        let isOn = defaults.boolForKey("ShadowsocksOn")
        if isOn {
            runningStatusMenuItem.title = "Shadowsocks: On".localized
            toggleRunningMenuItem.title = "Turn Shadowsocks Off".localized
            let image = NSImage(named: "menu_icon")
            statusItem.image = image
        } else {
            runningStatusMenuItem.title = "Shadowsocks: Off".localized
            toggleRunningMenuItem.title = "Turn Shadowsocks On".localized
            let image = NSImage(named: "menu_icon_disabled")
            statusItem.image = image
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
    
    func handleURLEvent(event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        if let urlString = event.paramDescriptorForKeyword(AEKeyword(keyDirectObject))?.stringValue {
            if let url = NSURL(string: urlString) {
                NSNotificationCenter.defaultCenter().postNotificationName(
                    "NOTIFY_FOUND_SS_URL", object: nil
                    , userInfo: [
                        "ruls": [url],
                        "source": "url",
                    ])
            }
        }
    }
    
    //------------------------------------------------------------
    // NSUserNotificationCenterDelegate
    
    func userNotificationCenter(center: NSUserNotificationCenter
        , shouldPresentNotification notification: NSUserNotification) -> Bool {
        return true
    }
}

