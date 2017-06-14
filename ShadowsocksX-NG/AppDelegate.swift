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
    
    // MARK: Controllers
    var qrcodeWinCtrl: SWBQRCodeWindowController!
    var preferencesWinCtrl: PreferencesWindowController!
    var advPreferencesWinCtrl: AdvPreferencesWindowController!
    var proxyPreferencesWinCtrl: ProxyPreferencesController!
    var editUserRulesWinCtrl: UserRulesController!
    var httpPreferencesWinCtrl : HTTPPreferencesWindowController!
    
    var launchAtLoginController: LaunchAtLoginController = LaunchAtLoginController()
    
    // MARK: Outlets
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var statusMenu: NSMenu!
    
    @IBOutlet weak var runningStatusMenuItem: NSMenuItem!
    @IBOutlet weak var toggleRunningMenuItem: NSMenuItem!
    @IBOutlet weak var proxyMenuItem: NSMenuItem!
    @IBOutlet weak var autoModeMenuItem: NSMenuItem!
    @IBOutlet weak var globalModeMenuItem: NSMenuItem!
    @IBOutlet weak var manualModeMenuItem: NSMenuItem!
    @IBOutlet weak var whiteListModeMenuItem: NSMenuItem!
    @IBOutlet weak var ACLModeMenuItem: NSMenuItem!
    @IBOutlet weak var ACLAutoModeMenuItem: NSMenuItem!
    @IBOutlet weak var ACLBackChinaMenuItem: NSMenuItem!
    
    @IBOutlet weak var serversMenuItem: NSMenuItem!
    @IBOutlet var pingserverMenuItem: NSMenuItem!
    @IBOutlet var showQRCodeMenuItem: NSMenuItem!
    @IBOutlet var scanQRCodeMenuItem: NSMenuItem!
    @IBOutlet var showBunchJsonExampleFileItem: NSMenuItem!
    @IBOutlet var importBunchJsonFileItem: NSMenuItem!
    @IBOutlet var exportAllServerProfileItem: NSMenuItem!
    @IBOutlet var serversPreferencesMenuItem: NSMenuItem!
    
    @IBOutlet weak var lanchAtLoginMenuItem: NSMenuItem!
    @IBOutlet weak var connectAtLaunchMenuItem: NSMenuItem!
    @IBOutlet weak var ShowNetworkSpeedItem: NSMenuItem!
    @IBOutlet weak var checkUpdateMenuItem: NSMenuItem!
    @IBOutlet weak var checkUpdateAtLaunchMenuItem: NSMenuItem!
    
    // MARK: Variables
    var statusItemView:StatusItemView!
    var statusItem: NSStatusItem?
    var speedMonitor:NetWorkMonitor?

    // MARK: Application function

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
            "PacServer.ListenAddress": "127.0.0.1",
            "PacServer.ListenPort":NSNumber(value: 8090 as UInt16),
            "LocalSocks5.Timeout": NSNumber(value: 60 as UInt),
            "LocalSocks5.EnableUDPRelay": NSNumber(value: false as Bool),
            "LocalSocks5.EnableVerboseMode": NSNumber(value: false as Bool),
            "GFWListURL": "https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt",
            "ACLWhiteListURL": "https://raw.githubusercontent.com/shadowsocksr/shadowsocksr-libev/master/acl/chn.acl",
            "ACLAutoListURL": "https://raw.githubusercontent.com/shadowsocksr/shadowsocksr-libev/master/acl/gfwlist.acl",
            "ACLProxyBackCHNURL":"https://raw.githubusercontent.com/shadowsocksr/ShadowsocksX-NG/develop/ShadowsocksX-NG/backchn.acl",
            "AutoConfigureNetworkServices": NSNumber(value: true as Bool),
            "LocalHTTP.ListenAddress": "127.0.0.1",
            "LocalHTTP.ListenPort": NSNumber(value: 1087 as UInt16),
            "LocalHTTPOn": true,
            "LocalHTTP.FollowGlobal": true,
            "AutoCheckUpdate": false,
            "ACLFileName": "chn.acl"
        ])

        setUpMenu(defaults.bool(forKey: "enable_showSpeed"))
        
        statusItem = NSStatusBar.system().statusItem(withLength: 20)
        let image = NSImage(named: "menu_icon")
        image?.isTemplate = true
        statusItem?.image = image
        statusItem?.menu = statusMenu

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
                self.updateMainMenu()
                self.updateRunningModeMenu()
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
                    let profielDict = ParseAppURLSchemes(url)//ParseSSURL(url)
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
                        userNote.informativeText = "Host: \(profile.serverHost)\n Port: \(profile.serverPort)\n Encription Method: \(profile.method)".localized
                        userNote.soundName = NSUserNotificationDefaultSoundName
                        
                        NSUserNotificationCenter.default
                            .deliver(userNote);
                    }else{
                        let userNote = NSUserNotification()
                        userNote.title = "Failed to Add Server Profile".localized
                        userNote.subtitle = "Address can not be recognized".localized
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
        applyConfig()
        SyncSSLocal()

        if defaults.bool(forKey: "ConnectAtLaunch") {
            toggleRunning(toggleRunningMenuItem)
        }
        // Version Check!
        if defaults.bool(forKey: "AutoCheckUpdate"){
            checkForUpdate(mustShowAlert: false)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
        StopSSLocal()
        StopPrivoxy()
        ProxyConfHelper.disableProxy("hi")
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: "ShadowsocksOn")
        ProxyConfHelper.stopPACServer()
    }
    
    func applyConfig() {
        let profileMgr = ServerProfileManager.instance
        if profileMgr.profiles.count == 0{
            let notice = NSUserNotification()
            notice.title = "还没有服务器设定！"
            notice.subtitle = "去设置里面填一下吧，填完记得选择呦~"
            NSUserNotificationCenter.default.deliver(notice)
        }
        let defaults = UserDefaults.standard
        let isOn = defaults.bool(forKey: "ShadowsocksOn")
        let mode = defaults.string(forKey: "ShadowsocksRunningMode")
        
        if isOn {
            StartSSLocal()
            StartPrivoxy()
            if mode == "auto" {
                ProxyConfHelper.disableProxy("hi")
                ProxyConfHelper.enablePACProxy("hi")
            } else if mode == "global" {
                ProxyConfHelper.disableProxy("hi")
                ProxyConfHelper.enableGlobalProxy()
            } else if mode == "manual" {
                ProxyConfHelper.disableProxy("hi")
                ProxyConfHelper.disableProxy("hi")
            } else if mode == "whiteList" {
                ProxyConfHelper.disableProxy("hi")
                ProxyConfHelper.enableWhiteListProxy()//新白名单基于GlobalMode
            }
        } else {
            StopSSLocal()
            StopPrivoxy()
            ProxyConfHelper.disableProxy("hi")
        }

    }
    
    // MARK: Mainmenu functions
    
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
    
    @IBAction func updateWhiteList(_ sender: NSMenuItem) {
        UpdateACL()
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
    
    @IBAction func toggleLaunghAtLogin(_ sender: NSMenuItem) {
        launchAtLoginController.launchAtLogin = !launchAtLoginController.launchAtLogin;
        updateLaunchAtLoginMenu()
    }
    
    @IBAction func toggleConnectAtLaunch(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: "ConnectAtLaunch"), forKey: "ConnectAtLaunch")
        updateMainMenu()
    }
    
    // MARK: Server submenu function

    @IBAction func showQRCodeForCurrentServer(_ sender: NSMenuItem) {
        var errMsg: String?
        if let profile = ServerProfileManager.instance.getActiveProfile() {
            if profile.isValid() {
                // Show window
                DispatchQueue.global().async {
                    if self.qrcodeWinCtrl != nil{
                        self.qrcodeWinCtrl.close()
                    }
                    self.qrcodeWinCtrl = SWBQRCodeWindowController(windowNibName: "SWBQRCodeWindowController")
                    self.qrcodeWinCtrl.qrCode = profile.URL()!.absoluteString
                    self.qrcodeWinCtrl.title = profile.title()
                    DispatchQueue.main.async {
                        self.qrcodeWinCtrl.showWindow(self)
                        NSApp.activate(ignoringOtherApps: true)
                        self.qrcodeWinCtrl.window?.makeKeyAndOrderFront(nil)
                    }
                }
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
    
    @IBAction func showBunchJsonExampleFile(_ sender: NSMenuItem) {
        ServerProfileManager.showExampleConfigFile()
    }
    
    @IBAction func importBunchJsonFile(_ sender: NSMenuItem) {
        ServerProfileManager.instance.importConfigFile()
        //updateServersMenu()//not working
    }
    
    @IBAction func exportAllServerProfile(_ sender: NSMenuItem) {
        ServerProfileManager.instance.exportConfigFile()
    }
    
    @IBAction func selectPACMode(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        defaults.setValue("auto", forKey: "ShadowsocksRunningMode")
        defaults.setValue("", forKey: "ACLFileName")
        updateRunningModeMenu()
        SyncSSLocal()
        applyConfig()
    }
    
    @IBAction func selectGlobalMode(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        defaults.setValue("global", forKey: "ShadowsocksRunningMode")
        defaults.setValue("", forKey: "ACLFileName")
        updateRunningModeMenu()
        SyncSSLocal()
        applyConfig()
    }
    
    @IBAction func selectManualMode(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        defaults.setValue("manual", forKey: "ShadowsocksRunningMode")
        defaults.setValue("", forKey: "ACLFileName")
        updateRunningModeMenu()
        SyncSSLocal()
        applyConfig()
    }
    @IBAction func selectACLAutoMode(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        defaults.setValue("whiteList", forKey: "ShadowsocksRunningMode")
        defaults.setValue("gfwlist.acl", forKey: "ACLFileName")
        updateRunningModeMenu()
        SyncSSLocal()
        applyConfig()
    }
    @IBAction func selectACLBackCHNMode(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        defaults.setValue("whiteList", forKey: "ShadowsocksRunningMode")
        defaults.setValue("backchn.acl", forKey: "ACLFileName")
        updateRunningModeMenu()
        SyncSSLocal()
        applyConfig()
    }
    @IBAction func selectWhiteListMode(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        defaults.setValue("whiteList", forKey: "ShadowsocksRunningMode")
        defaults.setValue("chn.acl", forKey: "ACLFileName")
        updateRunningModeMenu()
        SyncSSLocal()
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

    @IBAction func doPingTest(_ sender: AnyObject) {
        PingServers.instance.ping()
    }
    
    @IBAction func showSpeedTap(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        var enable = defaults.bool(forKey: "enable_showSpeed")
        enable = !enable
        setUpMenu(enable)
        defaults.set(enable, forKey: "enable_showSpeed")
        updateMainMenu()
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
        NSWorkspace.shared().open(URL(string: "https://github.com/shadowsocksr/ShadowsocksX-NG/issues")!)
    }
    
    @IBAction func checkForUpdate(_ sender: NSMenuItem) {
        checkForUpdate(mustShowAlert: true)
    }
    
    @IBAction func checkUpdatesAtLaunch(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: "AutoCheckUpdate"), forKey: "AutoCheckUpdate")
        checkUpdateAtLaunchMenuItem.state = defaults.bool(forKey: "AutoCheckUpdate") ? 1 : 0
    }
    
    @IBAction func showAbout(_ sender: NSMenuItem) {
        NSApp.orderFrontStandardAboutPanel(sender);
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func updateLaunchAtLoginMenu() {
        lanchAtLoginMenuItem.state = launchAtLoginController.launchAtLogin ? 1 : 0
    }
    
    // MARK: this function is use to update menu bar

    func updateRunningModeMenu() {
        let defaults = UserDefaults.standard
        let mode = defaults.string(forKey: "ShadowsocksRunningMode")
        var serverMenuText = "Servers".localized
        
        let mgr = ServerProfileManager.instance
        for p in mgr.profiles {
            if mgr.activeProfileId == p.uuid {
                if !p.remark.isEmpty {
                    serverMenuText = p.remark
                } else {
                    serverMenuText = p.serverHost
                }
                if let latency = p.latency{
                    serverMenuText += "  - \(latency) ms"
                }
                else{
                    if !neverSpeedTestBefore {
                        serverMenuText += "  - failed"
                    }
                }
            }
        }

        serversMenuItem.title = serverMenuText
        autoModeMenuItem.state = 0
        globalModeMenuItem.state = 0
        manualModeMenuItem.state = 0
        whiteListModeMenuItem.state = 0
        ACLBackChinaMenuItem.state = 0
        ACLAutoModeMenuItem.state = 0
        ACLModeMenuItem.state = 0
        if mode == "auto" {
            autoModeMenuItem.state = 1
        } else if mode == "global" {
            globalModeMenuItem.state = 1
        } else if mode == "manual" {
            manualModeMenuItem.state = 1
        } else if mode == "whiteList" {
            let aclMode = defaults.string(forKey: "ACLFileName")!
            switch aclMode {
            case "backchn.acl":
                ACLModeMenuItem.state = 1
                ACLBackChinaMenuItem.state = 1
                ACLModeMenuItem.title = "Proxy Back China".localized
                break
            case "gfwlist.acl":
                ACLModeMenuItem.state = 1
                ACLAutoModeMenuItem.state = 1
                ACLModeMenuItem.title = "ACL Auto".localized
                break
            default:
                whiteListModeMenuItem.state = 1
            }
        }
        updateStatusItemUI()
    }
    
    func updateStatusItemUI() {
        var image = NSImage()
        let defaults = UserDefaults.standard
        let mode = defaults.string(forKey: "ShadowsocksRunningMode")
        if !defaults.bool(forKey: "ShadowsocksOn") {
            return
        }
        if mode == "auto" {
            image = NSImage(named: "menu_icon_pac")!
            //statusItem?.title = "Auto".localized
        } else if mode == "global" {
            //statusItem?.title = "Global".localized
            image = NSImage(named: "menu_icon_global")!
        } else if mode == "manual" {
            image = NSImage(named: "menu_icon_manual")!
            //statusItem?.title = "Manual".localized
        } else if mode == "whiteList" {
            if defaults.string(forKey: "ACLFileName")! == "chn.acl" {
                image = NSImage(named: "menu_icon_white")!
            } else {
                image = NSImage(named: "menu_icon_acl")!
            }
        }
        let titleWidth:CGFloat = 0//statusItem?.title!.size(withAttributes: [NSFontAttributeName: statusItem?.button!.font!]).width//这里不包含IP白名单模式等等，需要重新调整//PS还是给上游加上白名单模式？
        let imageWidth:CGFloat = 22
        statusItem?.length = titleWidth + imageWidth
        image.isTemplate = true
        statusItem!.image = image
    }
    
    func updateMainMenu() {
        let defaults = UserDefaults.standard
        let isOn = defaults.bool(forKey: "ShadowsocksOn")
        var image = NSImage()
        if isOn {
            runningStatusMenuItem.title = "Shadowsocks: On".localized
            toggleRunningMenuItem.title = "Turn Shadowsocks Off".localized
            //image = NSImage(named: "menu_icon")!
            updateStatusItemUI()
        } else {
            runningStatusMenuItem.title = "Shadowsocks: Off".localized
            toggleRunningMenuItem.title = "Turn Shadowsocks On".localized
            image = NSImage(named: "menu_icon_disabled")!
            image.isTemplate = true
            statusItem!.image = image
        }

        ShowNetworkSpeedItem.state          = defaults.bool(forKey: "enable_showSpeed") ? 1 : 0
        connectAtLaunchMenuItem.state       = defaults.bool(forKey: "ConnectAtLaunch")  ? 1 : 0
        checkUpdateAtLaunchMenuItem.state   = defaults.bool(forKey: "AutoCheckUpdate")  ? 1 : 0
    }
    
    func updateServersMenu() {
        let mgr = ServerProfileManager.instance
        serversMenuItem.submenu?.removeAllItems()
        let showQRItem = showQRCodeMenuItem
        let scanQRItem = scanQRCodeMenuItem
        let preferencesItem = serversPreferencesMenuItem
        let showBunch = showBunchJsonExampleFileItem
        let importBuntch = importBunchJsonFileItem
        let exportAllServer = exportAllServerProfileItem
//        let pingItem = pingserverMenuItem

        var i = 0
        for p in mgr.profiles {
            let item = NSMenuItem()
            item.tag = i //+ kProfileMenuItemIndexBase
            item.title = p.title()
            if let latency = p.latency{
                item.title += "  - \(latency) ms"
            }else{
                if !neverSpeedTestBefore {
                    item.title += "  - failed"
                }
            }
            if mgr.activeProfileId == p.uuid {
                item.state = 1
            }
            if !p.isValid() {
                item.isEnabled = false
            }
            
            item.action = #selector(AppDelegate.selectServer)
            
            if !p.ssrGroup.isEmpty {
                if((serversMenuItem.submenu?.item(withTitle: p.ssrGroup)) == nil){
                    let groupSubmenu = NSMenu()
                    let groupSubmenuItem = NSMenuItem()
                    groupSubmenuItem.title = p.ssrGroup
                    serversMenuItem.submenu?.addItem(groupSubmenuItem)
                    serversMenuItem.submenu?.setSubmenu(groupSubmenu, for: groupSubmenuItem)
                    if mgr.activeProfileId == p.uuid {
                        item.state = 1
                        groupSubmenuItem.state = 1
                    }
                    groupSubmenuItem.submenu?.addItem(item)
                    i += 1
                    continue
                }
                else{
                    if mgr.activeProfileId == p.uuid {
                        item.state = 1
                        serversMenuItem.submenu?.item(withTitle: p.ssrGroup)?.state = 1
                    }
                    serversMenuItem.submenu?.item(withTitle: p.ssrGroup)?.submenu?.addItem(item)
                    i += 1
                    continue
                }
            }
            
            serversMenuItem.submenu?.addItem(item)
            i += 1
        }
        if !mgr.profiles.isEmpty {
            serversMenuItem.submenu?.addItem(NSMenuItem.separator())
        }
        serversMenuItem.submenu?.addItem(showQRItem!)
        serversMenuItem.submenu?.addItem(scanQRItem!)
        serversMenuItem.submenu?.addItem(showBunch!)
        serversMenuItem.submenu?.addItem(importBuntch!)
        serversMenuItem.submenu?.addItem(exportAllServer!)
        serversMenuItem.submenu?.addItem(NSMenuItem.separator())
        serversMenuItem.submenu?.addItem(preferencesItem!)
//        serversMenuItem.submenu?.addItem(pingItem)

    }
    
    func setUpMenu(_ showSpeed:Bool){
        // should not operate the system status bar
        // we can add sub menu like bittorrent sync
//        if statusItem == nil{
//            statusItem = NSStatusBar.system().statusItem(withLength: 85)
//            let image = NSImage(named: "menu_icon")
//            image?.isTemplate = true
//            statusItem!.image = image
//            statusItemView = StatusItemView(statusItem: statusItem!, menu: statusMenu)
//            statusItem!.view = statusItemView
//        }
//        if showSpeed{
//            if speedMonitor == nil{
//                speedMonitor = NetWorkMonitor(statusItemView: statusItemView)
//            }
//            statusItem?.length = 85
//            speedMonitor?.start()
//        }else{
//            speedMonitor?.stop()
//            speedMonitor = nil
//            statusItem?.length = 20
//        }
    }
    
    func checkForUpdate(mustShowAlert: Bool) -> Void {
        let versionChecker = VersionChecker()
        DispatchQueue.global().async {
            let newVersion = versionChecker.checkNewVersion()
            DispatchQueue.main.async {
                if (mustShowAlert || newVersion["newVersion"] as! Bool){
                    let alertResult = versionChecker.showAlertView(Title: newVersion["Title"] as! String, SubTitle: newVersion["SubTitle"] as! String, ConfirmBtn: newVersion["ConfirmBtn"] as! String, CancelBtn: newVersion["CancelBtn"] as! String)
                    print(alertResult)
                    if (newVersion["newVersion"] as! Bool && alertResult == 1000){
                        NSWorkspace.shared().open(URL(string: "https://github.com/shadowsocksr/ShadowsocksX-NG/releases")!)
                    }
                }
            }
        }
    }
    
    // MARK: 

    func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        if let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue {
            if URL(string: urlString) != nil {
                NotificationCenter.default.post(
                    name: Notification.Name(rawValue: "NOTIFY_FOUND_SS_URL"), object: nil
                    , userInfo: [
                        "urls": splitProfile(url: urlString, max: 5).map({ (item: String) -> URL in
                            return URL(string: item)!
                        }),
                        "source": "url",
                    ])
            }
        }
    }
    
    //------------------------------------------------------------
    // MARK: NSUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: NSUserNotificationCenter
        , shouldPresent notification: NSUserNotification) -> Bool {
        return true
    }
}

