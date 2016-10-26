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
    var proxyPreferencesWinCtrl: ProxyPreferencesController!
    var editUserRulesWinCtrl: UserRulesController!
    var httpPreferencesWinCtrl : HTTPPreferencesWindowController!
    
    var launchAtLoginController: LaunchAtLoginController = LaunchAtLoginController()
    
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var statusMenu: NSMenu!
    
    @IBOutlet weak var runningStatusMenuItem: NSMenuItem!
    @IBOutlet weak var toggleRunningMenuItem: NSMenuItem!
    @IBOutlet weak var proxyMenuItem: NSMenuItem!
    @IBOutlet weak var autoModeMenuItem: NSMenuItem!
    @IBOutlet weak var globalModeMenuItem: NSMenuItem!
    @IBOutlet weak var manualModeMenuItem: NSMenuItem!
    @IBOutlet weak var showRunningModeMenuItem: NSMenuItem!
    
    @IBOutlet weak var serversMenuItem: NSMenuItem!
    @IBOutlet var showQRCodeMenuItem: NSMenuItem!
    @IBOutlet var scanQRCodeMenuItem: NSMenuItem!
    @IBOutlet var serversPreferencesMenuItem: NSMenuItem!
    
    @IBOutlet weak var lanchAtLoginMenuItem: NSMenuItem!
    
    var statusItem: NSStatusItem!
    
    static let StatusItemIconWidth:CGFloat = 20
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
        
        NSUserNotificationCenter.default.delegate = self
        
        // Prepare ss-local
        InstallSSLocal()
        InstallPrivoxy()
        // Prepare defaults
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "ShadowsocksOn": true,
            "ShadowsocksRunningMode": "auto",
            "LocalSocks5.ListenPort": NSNumber(value: 1086 as UInt16),
            "LocalSocks5.ListenAddress": "127.0.0.1",
            "PacServer.ListenPort":NSNumber(value: 8090 as UInt16),
            "LocalSocks5.Timeout": NSNumber(value: 60 as UInt),
            "LocalSocks5.EnableUDPRelay": NSNumber(value: false as Bool),
            "LocalSocks5.EnableVerboseMode": NSNumber(value: false as Bool),
            "GFWListURL": "https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt",
            "AutoConfigureNetworkServices": NSNumber(value: true as Bool),
            "LocalHTTP.ListenAddress": "127.0.0.1",
            "LocalHTTP.ListenPort": NSNumber(value: 1087 as UInt16),
            "LocalHTTPOn": true,
            "LocalHTTP.FollowGlobal": true
            ])
        
        statusItem = NSStatusBar.system().statusItem(withLength: AppDelegate.StatusItemIconWidth)
        let image = NSImage(named: "menu_icon")
        image?.isTemplate = true
        statusItem.image = image
        statusItem.menu = statusMenu
        
        
        let notifyCenter = NotificationCenter.default
        notifyCenter.addObserver(forName: NSNotification.Name(rawValue: NOTIFY_ADV_PROXY_CONF_CHANGED), object: nil, queue: nil
            , using: {
                (note) in
                self.applyConfig()
            }
        )
        notifyCenter.addObserver(forName: NSNotification.Name(rawValue: NOTIFY_SERVER_PROFILES_CHANGED), object: nil, queue: nil
            , using: {
                (note) in
                let profileMgr = ServerProfileManager.instance
                if profileMgr.activeProfileId == nil &&
                    profileMgr.profiles.count > 0{
                    if profileMgr.profiles[0].isValid(){
                        profileMgr.setActiveProfiledId(profileMgr.profiles[0].uuid)
                    }
                }
                self.updateServersMenu()
                SyncSSLocal()
            }
        )
        notifyCenter.addObserver(forName: NSNotification.Name(rawValue: NOTIFY_ADV_CONF_CHANGED), object: nil, queue: nil
            , using: {
                (note) in
                SyncSSLocal()
                self.applyConfig()
            }
        )
        notifyCenter.addObserver(forName: NSNotification.Name(rawValue: NOTIFY_HTTP_CONF_CHANGED), object: nil, queue: nil
            , using: {
                (note) in
                SyncPrivoxy()
                self.applyConfig()
            }
        )
        notifyCenter.addObserver(forName: NSNotification.Name(rawValue: "NOTIFY_FOUND_SS_URL"), object: nil, queue: nil) {
            (note: Notification) in
            if let userInfo = (note as NSNotification).userInfo {
                let urls: [URL] = userInfo["urls"] as! [URL]
                
                let mgr = ServerProfileManager.instance
                var isChanged = false
                
                for url in urls {
                    let profielDict = ParseSSURL(url)
                    if let profielDict = profielDict {
                        let profile = ServerProfile.fromDictionary(profielDict as [String : AnyObject])
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
                        
                        NSUserNotificationCenter.default
                            .deliver(userNote);
                    }
                }
                
                if isChanged {
                    mgr.save()
                    self.updateServersMenu()
                }
            }
        }
        
        // Handle ss url scheme
        NSAppleEventManager.shared().setEventHandler(self
            , andSelector: #selector(self.handleURLEvent)
            , forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        
        updateMainMenu()
        updateServersMenu()
        updateRunningModeMenu()
        updateLaunchAtLoginMenu()
        
        ProxyConfHelper.install()
        ProxyConfHelper.startMonitorPAC()
        applyConfig()
        SyncSSLocal()
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
        StopSSLocal()
        StopPrivoxy()
        ProxyConfHelper.disableProxy()
    }
    
    func applyConfig() {
        let defaults = UserDefaults.standard
        let isOn = defaults.bool(forKey: "ShadowsocksOn")
        let mode = defaults.string(forKey: "ShadowsocksRunningMode")
        
        if isOn {
            StartSSLocal()
            StartPrivoxy()
            if mode == "auto" {
                ProxyConfHelper.enablePACProxy()
            } else if mode == "global" {
                ProxyConfHelper.enableGlobalProxy()
            } else if mode == "manual" {
                ProxyConfHelper.disableProxy()
            }
        } else {
            StopSSLocal()
            StopPrivoxy()
            ProxyConfHelper.disableProxy()
        }
    }
    
    @IBAction func toggleRunning(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        var isOn = defaults.bool(forKey: "ShadowsocksOn")
        isOn = !isOn
        defaults.set(isOn, forKey: "ShadowsocksOn")
        
        updateMainMenu()
        
        applyConfig()
    }
    
    @IBAction func updateGFWList(_ sender: NSMenuItem) {
        UpdatePACFromGFWList()
    }
    
    @IBAction func editUserRulesForPAC(_ sender: NSMenuItem) {
        if editUserRulesWinCtrl != nil {
            editUserRulesWinCtrl.close()
        }
        let ctrl = UserRulesController(windowNibName: "UserRulesController")
        editUserRulesWinCtrl = ctrl
        
        ctrl.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
        ctrl.window?.makeKeyAndOrderFront(self)
    }
    
    @IBAction func showQRCodeForCurrentServer(_ sender: NSMenuItem) {
        var errMsg: String?
        if let profile = ServerProfileManager.instance.getActiveProfile() {
            if profile.isValid() {
                // Show window
                if qrcodeWinCtrl != nil{
                    qrcodeWinCtrl.close()
                }
                qrcodeWinCtrl = SWBQRCodeWindowController(windowNibName: "SWBQRCodeWindowController")
                qrcodeWinCtrl.qrCode = profile.URL()!.absoluteString
                qrcodeWinCtrl.showWindow(self)
                NSApp.activate(ignoringOtherApps: true)
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
        
        NSUserNotificationCenter.default
            .deliver(userNote);
    }
    
    @IBAction func scanQRCodeFromScreen(_ sender: NSMenuItem) {
        ScanQRCodeOnScreen()
    }
    
    @IBAction func toggleLaunghAtLogin(_ sender: NSMenuItem) {
        launchAtLoginController.launchAtLogin = !launchAtLoginController.launchAtLogin;
        updateLaunchAtLoginMenu()
    }
    
    @IBAction func selectPACMode(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        defaults.setValue("auto", forKey: "ShadowsocksRunningMode")
        updateRunningModeMenu()
        applyConfig()
    }
    
    @IBAction func selectGlobalMode(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        defaults.setValue("global", forKey: "ShadowsocksRunningMode")
        updateRunningModeMenu()
        applyConfig()
    }
    
    @IBAction func selectManualMode(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        defaults.setValue("manual", forKey: "ShadowsocksRunningMode")
        updateRunningModeMenu()
        applyConfig()
    }
    
    @IBAction func editServerPreferences(_ sender: NSMenuItem) {
        if preferencesWinCtrl != nil {
            preferencesWinCtrl.close()
        }
        let ctrl = PreferencesWindowController(windowNibName: "PreferencesWindowController")
        preferencesWinCtrl = ctrl
        
        ctrl.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
        ctrl.window?.makeKeyAndOrderFront(self)
    }
    
    @IBAction func editAdvPreferences(_ sender: NSMenuItem) {
        if advPreferencesWinCtrl != nil {
            advPreferencesWinCtrl.close()
        }
        let ctrl = AdvPreferencesWindowController(windowNibName: "AdvPreferencesWindowController")
        advPreferencesWinCtrl = ctrl
        
        ctrl.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
        ctrl.window?.makeKeyAndOrderFront(self)
    }
    
    @IBAction func editHTTPPreferences(_ sender: NSMenuItem) {
        if httpPreferencesWinCtrl != nil {
            httpPreferencesWinCtrl.close()
        }
        let ctrl = HTTPPreferencesWindowController(windowNibName: "HTTPPreferencesWindowController")
        httpPreferencesWinCtrl = ctrl
        
        ctrl.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
        ctrl.window?.makeKeyAndOrderFront(self)
    }
    
    @IBAction func editProxyPreferences(_ sender: NSObject) {
        if proxyPreferencesWinCtrl != nil {
            proxyPreferencesWinCtrl.close()
        }
        proxyPreferencesWinCtrl = ProxyPreferencesController(windowNibName: "ProxyPreferencesController")
        proxyPreferencesWinCtrl.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
        proxyPreferencesWinCtrl.window?.makeKeyAndOrderFront(self)
    }
    
    @IBAction func selectServer(_ sender: NSMenuItem) {
        let index = sender.tag
        let spMgr = ServerProfileManager.instance
        let newProfile = spMgr.profiles[index]
        if newProfile.uuid != spMgr.activeProfileId {
            spMgr.setActiveProfiledId(newProfile.uuid)
            updateServersMenu()
            SyncSSLocal()
        }
        updateRunningModeMenu()
    }
    
    @IBAction func showLogs(_ sender: NSMenuItem) {
        let ws = NSWorkspace.shared()
        if let appUrl = ws.urlForApplication(withBundleIdentifier: "com.apple.Console") {
            try! ws.launchApplication(at: appUrl
                ,options: .default
                ,configuration: [NSWorkspaceLaunchConfigurationArguments: "~/Library/Logs/ss-local.log"])
        }
    }
    
    @IBAction func feedback(_ sender: NSMenuItem) {
        NSWorkspace.shared().open(URL(string: "https://github.com/qiuyuzhou/ShadowsocksX-NG/issues")!)
    }
    
    @IBAction func showAbout(_ sender: NSMenuItem) {
        NSApp.orderFrontStandardAboutPanel(sender);
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @IBAction func showRunningMode(_ sender: NSMenuItem) {
        sender.state = sender.state == 1 ? 0 : 1
        let defaults = UserDefaults.standard
        let isShown = (sender.state == 1)
        defaults.set(isShown, forKey: "ShowRunningModeOnStatusBar")
        updateStatusItemUI(isShownnRunningMode: isShown)
    }
    
    func updateLaunchAtLoginMenu() {
        if launchAtLoginController.launchAtLogin {
            lanchAtLoginMenuItem.state = 1
        } else {
            lanchAtLoginMenuItem.state = 0
        }
    }
    
    func updateRunningModeMenu() {
        let defaults = UserDefaults.standard
        let mode = defaults.string(forKey: "ShadowsocksRunningMode")
        
        showRunningModeMenuItem.title = "Show Running Mode On Status Bar".localized
        showRunningModeMenuItem.state = defaults.bool(forKey: "ShowRunningModeOnStatusBar") ? 1 : 0
        
        var serverMenuText = "Servers".localized

        let mgr = ServerProfileManager.instance
        for p in mgr.profiles {
            if mgr.activeProfileId == p.uuid {
                var profileName :String
                if !p.remark.isEmpty {
                    profileName = p.remark
                } else {
                    profileName = p.serverHost
                }
                serverMenuText = "\(serverMenuText) - \(profileName)"
            }
        }
        serversMenuItem.title = serverMenuText
        
        if mode == "auto" {
            proxyMenuItem.title = "Proxy - Auto By PAC".localized
            autoModeMenuItem.state = 1
            globalModeMenuItem.state = 0
            manualModeMenuItem.state = 0
        } else if mode == "global" {
            proxyMenuItem.title = "Proxy - Global".localized
            autoModeMenuItem.state = 0
            globalModeMenuItem.state = 1
            manualModeMenuItem.state = 0
        } else if mode == "manual" {
            proxyMenuItem.title = "Proxy - Manual".localized
            autoModeMenuItem.state = 0
            globalModeMenuItem.state = 0
            manualModeMenuItem.state = 1
        }
        let isShown = defaults.bool(forKey: "ShowRunningModeOnStatusBar")
        updateStatusItemUI(isShownnRunningMode: isShown)
    }
    
    func updateStatusItemUI(isShownnRunningMode: Bool) {
        if isShownnRunningMode {
            let defaults = UserDefaults.standard
            let mode = defaults.string(forKey: "ShadowsocksRunningMode")
            if mode == "auto" {
                statusItem.title = "Auto".localized
            } else if mode == "global" {
                statusItem.title = "Global".localized
            } else if mode == "manual" {
                statusItem.title = "Manual".localized
            }
            let titleWidth = statusItem.title!.size(withAttributes: [NSFontAttributeName: statusItem.button!.font!]).width
            let imageWidth:CGFloat = AppDelegate.StatusItemIconWidth
            statusItem.length = titleWidth + imageWidth + 2
        } else {
            statusItem.length = AppDelegate.StatusItemIconWidth
        }
    }
    
    func updateMainMenu() {
        let defaults = UserDefaults.standard
        let isOn = defaults.bool(forKey: "ShadowsocksOn")
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
        let mgr = ServerProfileManager.instance
        serversMenuItem.submenu?.removeAllItems()
        let showQRItem = showQRCodeMenuItem
        let scanQRItem = scanQRCodeMenuItem
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
                item.isEnabled = false
            }
            item.action = #selector(AppDelegate.selectServer)
            
            serversMenuItem.submenu?.addItem(item)
            i += 1
        }
        if !mgr.profiles.isEmpty {
            serversMenuItem.submenu?.addItem(NSMenuItem.separator())
        }
        serversMenuItem.submenu?.addItem(showQRItem!)
        serversMenuItem.submenu?.addItem(scanQRItem!)
        serversMenuItem.submenu?.addItem(NSMenuItem.separator())
        serversMenuItem.submenu?.addItem(preferencesItem!)
    }
    
    func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        if let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue {
            if let url = URL(string: urlString) {
                NotificationCenter.default.post(
                    name: Notification.Name(rawValue: "NOTIFY_FOUND_SS_URL"), object: nil
                    , userInfo: [
                        "ruls": [url],
                        "source": "url",
                        ])
            }
        }
    }
    
    //------------------------------------------------------------
    // NSUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: NSUserNotificationCenter
        , shouldPresent notification: NSUserNotification) -> Bool {
        return true
    }
}

