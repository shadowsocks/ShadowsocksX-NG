//
//  AppDelegate.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/5.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Cocoa
import Carbon
import RxCocoa
import RxSwift

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate {
    
    var shareWinCtrl: ShareServerProfilesWindowController!
    var qrcodeWinCtrl: SWBQRCodeWindowController!
    var preferencesWinCtrl: PreferencesWindowController!
    var editUserRulesWinCtrl: UserRulesController!
    var allInOnePreferencesWinCtrl: PreferencesWinController!
    var toastWindowCtrl: ToastWindowController!
    var importWinCtrl: ImportWindowController!

    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var statusMenu: NSMenu!
    
    @IBOutlet weak var runningStatusMenuItem: NSMenuItem!
    @IBOutlet weak var toggleRunningMenuItem: NSMenuItem!
    @IBOutlet weak var autoModeMenuItem: NSMenuItem!
    @IBOutlet weak var globalModeMenuItem: NSMenuItem!
    @IBOutlet weak var manualModeMenuItem: NSMenuItem!
    @IBOutlet weak var externalPACModeMenuItem: NSMenuItem!
    
    @IBOutlet weak var serversMenuItem: NSMenuItem!
    @IBOutlet var showQRCodeMenuItem: NSMenuItem!
    @IBOutlet var scanQRCodeMenuItem: NSMenuItem!
    @IBOutlet var serverProfilesBeginSeparatorMenuItem: NSMenuItem!
    @IBOutlet var serverProfilesEndSeparatorMenuItem: NSMenuItem!
    
    @IBOutlet weak var copyHttpProxyExportCmdLineMenuItem: NSMenuItem!
    
    @IBOutlet weak var lanchAtLoginMenuItem: NSMenuItem!

    @IBOutlet weak var hudWindow: NSPanel!
    @IBOutlet weak var panelView: NSView!
    @IBOutlet weak var isNameTextField: NSTextField!

    let kProfileMenuItemIndexBase = 100

    var statusItem: NSStatusItem!
    static let StatusItemIconWidth: CGFloat = NSStatusItem.variableLength
    
    func ensureLaunchAgentsDirOwner () {
        let dirPath = NSHomeDirectory() + "/Library/LaunchAgents"
        let fileMgr = FileManager.default
        if fileMgr.fileExists(atPath: dirPath) {
            do {
                let attrs = try fileMgr.attributesOfItem(atPath: dirPath)
                if attrs[FileAttributeKey.ownerAccountName] as! String != NSUserName() {
                    //try fileMgr.setAttributes([FileAttributeKey.ownerAccountName: NSUserName()], ofItemAtPath: dirPath)
                    let bashFilePath = Bundle.main.path(forResource: "fix_dir_owner.sh", ofType: nil)!
                    let script = "do shell script \"bash \\\"\(bashFilePath)\\\" \(NSUserName()) \" with administrator privileges"
                    if let appleScript = NSAppleScript(source: script) {
                        var err: NSDictionary? = nil
                        appleScript.executeAndReturnError(&err)
                    }
                }
            }
            catch {
                NSLog("Error when ensure the owner of $HOME/Library/LaunchAgents, \(error.localizedDescription)")
            }
        }
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        _ = LaunchAtLoginController()// Ensure set when launch
        
        NSUserNotificationCenter.default.delegate = self
        
        self.ensureLaunchAgentsDirOwner()
        
        // Prepare ss-local
        InstallSSLocal()
        InstallPrivoxy()
        InstallSimpleObfs()
        InstallKcptun()
        InstallV2rayPlugin()
        
        // Prepare defaults
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "ShadowsocksOn": true,
            "ShadowsocksRunningMode": "auto",
            "LocalSocks5.ListenPort": NSNumber(value: 1086 as UInt16),
            "LocalSocks5.ListenAddress": "127.0.0.1",
            "PacServer.BindToLocalhost": NSNumber(value: true as Bool),
            "PacServer.ListenPort":NSNumber(value: 1089 as UInt16),
            "LocalSocks5.Timeout": NSNumber(value: 60 as UInt),
            "LocalSocks5.EnableUDPRelay": NSNumber(value: false as Bool),
            "LocalSocks5.EnableVerboseMode": NSNumber(value: false as Bool),
            "GFWListURL": "https://cdn.jsdelivr.net/gh/gfwlist/gfwlist/gfwlist.txt",
            "AutoConfigureNetworkServices": NSNumber(value: true as Bool),
            "LocalHTTP.ListenAddress": "127.0.0.1",
            "LocalHTTP.ListenPort": NSNumber(value: 1087 as UInt16),
            "LocalHTTPOn": true,
            "LocalHTTP.FollowGlobal": false,
            "ProxyExceptions": "127.0.0.1, localhost, 192.168.0.0/16, 10.0.0.0/8, FE80::/64, ::1, FD00::/8",
            "ExternalPACURL": "",
            "EnableSwitchMode.PAC": true,
            "EnableSwitchMode.Global": true,
            "EnableSwitchMode.Manual": false,
            "EnableSwitchMode.ExternalPAC": false,
            ])
        
        statusItem = NSStatusBar.system.statusItem(withLength: AppDelegate.StatusItemIconWidth)
        let image : NSImage = NSImage(named: "menu_icon")!
        image.isTemplate = true
        statusItem.image = image
        statusItem.menu = statusMenu
        
        let notifyCenter = NotificationCenter.default
        
        _ = notifyCenter.rx.notification(NOTIFY_CONF_CHANGED)
            .subscribe(onNext: { noti in
                self.applyConfig()
                self.updateRunningModeMenu()
                self.updateCopyHttpProxyExportMenu()
            })
        
        notifyCenter.addObserver(forName: NOTIFY_SERVER_PROFILES_CHANGED, object: nil, queue: nil
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
                self.updateRunningModeMenu()
                SyncSSLocal()
            }
        )
        _ = notifyCenter.rx.notification(NOTIFY_TOGGLE_RUNNING_SHORTCUT)
            .subscribe(onNext: { noti in
                self.doToggleRunning(showToast: true)
            })
        _ = notifyCenter.rx.notification(NOTIFY_SWITCH_PROXY_MODE_SHORTCUT)
            .subscribe(onNext: { noti in
                let mode = defaults.string(forKey: "ShadowsocksRunningMode")!
                
                var enabledModeList: [String] = []
                if defaults.bool(forKey: "EnableSwitchMode.PAC") {
                    enabledModeList.append("auto")
                }
                if defaults.bool(forKey: "EnableSwitchMode.Global") {
                    enabledModeList.append("global")
                }
                if defaults.bool(forKey: "EnableSwitchMode.Manual") {
                    enabledModeList.append("manual")
                }
                if defaults.bool(forKey: "EnableSwitchMode.ExternalPAC")
                    && self.externalPACModeMenuItem.isEnabled {
                    enabledModeList.append("externalPAC")
                }
                
                if enabledModeList.isEmpty {
                    return
                }
                
                var nextMode = ""
                if enabledModeList.contains(mode) {
                    let i = enabledModeList.firstIndex(of: mode)!
                    if i + 1 == enabledModeList.count {
                        nextMode = enabledModeList[0]
                    } else {
                        nextMode = enabledModeList[i+1]
                    }
                } else {
                    nextMode = enabledModeList[0]
                }
                
                defaults.setValue(nextMode, forKey: "ShadowsocksRunningMode")
                
                self.updateRunningModeMenu()
                self.applyConfig()
                
                // Show toast message
                let toastMessages = [
                    "auto": "Auto Mode By PAC".localized,
                    "global": "Global Mode".localized,
                    "manual": "Manual Mode".localized,
                    "externalPAC": "Auto Mode By External PAC".localized,
                ]
                self.makeToast(toastMessages[nextMode]!)
            })
        
        _ = notifyCenter.rx.notification(NOTIFY_FOUND_SS_URL)
            .subscribe(onNext: { noti in
                self.handleFoundSSURL(noti)
            })
        
        // Handle ss url scheme
        NSAppleEventManager.shared().setEventHandler(self
            , andSelector: #selector(self.handleURLEvent)
            , forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        
        updateMainMenu()
        updateCopyHttpProxyExportMenu()
        updateServersMenu()
        updateRunningModeMenu()
        
        ProxyConfHelper.install()
        ProxyConfHelper.startMonitorPAC()
        applyConfig()

        // Register global hotkey
        ShortcutsController.bindShortcuts()
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
        StopSSLocal()
        StopPrivoxy()
        ProxyConfHelper.disableProxy()
    }

    func applyConfig() {
        SyncSSLocal()
        
        let defaults = UserDefaults.standard
        let isOn = defaults.bool(forKey: "ShadowsocksOn")
        let mode = defaults.string(forKey: "ShadowsocksRunningMode")
        
        if isOn {
            if mode == "auto" {
                ProxyConfHelper.enablePACProxy()
            } else if mode == "global" {
                ProxyConfHelper.enableGlobalProxy()
            } else if mode == "manual" {
                ProxyConfHelper.disableProxy()
            } else if mode == "externalPAC" {
                ProxyConfHelper.enableExternalPACProxy()
            }
        } else {
            ProxyConfHelper.disableProxy()
        }
    }

    // MARK: - UI Methods
    @IBAction func toggleRunning(_ sender: NSMenuItem) {
        self.doToggleRunning(showToast: false)
    }
    
    func doToggleRunning(showToast: Bool) {
        let defaults = UserDefaults.standard
        var isOn = UserDefaults.standard.bool(forKey: "ShadowsocksOn")
        isOn = !isOn
        defaults.set(isOn, forKey: "ShadowsocksOn")
        
        self.updateMainMenu()
        self.applyConfig()
        
        if showToast {
            if isOn {
                self.makeToast("Shadowsocks: On".localized)
            }
            else {
                self.makeToast("Shadowsocks: Off".localized)
            }
        }
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
    
    @IBAction func showShareServerProfiles(_ sender: NSMenuItem) {
        if shareWinCtrl != nil {
            shareWinCtrl.close()
        }
        shareWinCtrl = ShareServerProfilesWindowController(windowNibName: "ShareServerProfilesWindowController")
        shareWinCtrl.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
        shareWinCtrl.window?.makeKeyAndOrderFront(nil)
    }
    
    @IBAction func showImportWindow(_ sender: NSMenuItem) {
        if importWinCtrl != nil {
            importWinCtrl.close()
        }
        importWinCtrl = ImportWindowController(windowNibName: "ImportWindowController")
        importWinCtrl.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
        importWinCtrl.window?.makeKeyAndOrderFront(nil)
    }
    
    @IBAction func scanQRCodeFromScreen(_ sender: NSMenuItem) {
        ScanQRCodeOnScreen()
    }
    
    @IBAction func importProfileURLFromPasteboard(_ sender: NSMenuItem) {
        let pb = NSPasteboard.general
        if #available(OSX 10.13, *) {
            if let text = pb.string(forType: NSPasteboard.PasteboardType.URL) {
                if let url = URL(string: text) {
                    NotificationCenter.default.post(
                        name: NOTIFY_FOUND_SS_URL, object: nil
                        , userInfo: [
                            "urls": [url],
                            "source": "pasteboard",
                            ])
                }
            }
        }
        if let text = pb.string(forType: NSPasteboard.PasteboardType.string) {
            var urls = text.split(separator: "\n")
                .map { String($0).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                .map { URL(string: $0) }
                .filter { $0 != nil }
                .map { $0! }
            urls = urls.filter { $0.scheme == "ss" }
            
            NotificationCenter.default.post(
                name: NOTIFY_FOUND_SS_URL, object: nil
                , userInfo: [
                    "urls": urls,
                    "source": "pasteboard",
                    ])
        }
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
    
    @IBAction func selectExternalPACMode(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        defaults.setValue("externalPAC", forKey: "ShadowsocksRunningMode")
        updateRunningModeMenu()
        applyConfig()
    }
    
    @IBAction func editServerPreferences(_ sender: NSMenuItem) {
        if preferencesWinCtrl != nil {
            preferencesWinCtrl.close()
        }
        preferencesWinCtrl = PreferencesWindowController(windowNibName: "PreferencesWindowController")
        
        preferencesWinCtrl.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @IBAction func showAllInOnePreferences(_ sender: NSMenuItem) {
        if allInOnePreferencesWinCtrl != nil {
            allInOnePreferencesWinCtrl.close()
        }
        
        allInOnePreferencesWinCtrl = PreferencesWinController(windowNibName: "PreferencesWinController")
        
        allInOnePreferencesWinCtrl.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
        allInOnePreferencesWinCtrl.window?.makeKeyAndOrderFront(self)
    }
    
    @IBAction func selectServer(_ sender: NSMenuItem) {
        let index = sender.tag - kProfileMenuItemIndexBase
        let spMgr = ServerProfileManager.instance
        let newProfile = spMgr.profiles[index]
        if newProfile.uuid != spMgr.activeProfileId {
            spMgr.setActiveProfiledId(newProfile.uuid)
            updateServersMenu()
            SyncSSLocal()
            applyConfig()
        }
        updateRunningModeMenu()
    }
    
    @IBAction func copyExportCommand(_ sender: NSMenuItem) {
        // Get the Http proxy config.
        let defaults = UserDefaults.standard
        let address = defaults.string(forKey: "LocalHTTP.ListenAddress")!
        let port = defaults.integer(forKey: "LocalHTTP.ListenPort")
        
        // Format an export string.
        let command = "export http_proxy=http://\(address):\(port);export https_proxy=http://\(address):\(port);"
        
        // Copy to paste board.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: NSPasteboard.PasteboardType.string)
        
        // Show a toast notification.
        self.makeToast("Export Command Copied.".localized)
    }
    
    @IBAction func showLogs(_ sender: NSMenuItem) {
        let ws = NSWorkspace.shared
        if let appUrl = ws.urlForApplication(withBundleIdentifier: "com.apple.Console") {
            try! ws.launchApplication(at: appUrl
                ,options: NSWorkspace.LaunchOptions.default
                ,configuration: [NSWorkspace.LaunchConfigurationKey.arguments: "~/Library/Logs/ss-local.log"])
        }
    }
    
    @IBAction func feedback(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(URL(string: "https://github.com/qiuyuzhou/ShadowsocksX-NG/issues")!)
    }
    
    @IBAction func checkForUpdates(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(URL(string: "https://github.com/shadowsocks/ShadowsocksX-NG/releases")!)
    }
    
    @IBAction func exportDiagnosis(_ sender: NSMenuItem) {
        let savePanel = NSSavePanel()
        savePanel.title = "Save Diagnosis to File".localized
        savePanel.canCreateDirectories = true
        savePanel.allowedFileTypes = ["txt"]
        savePanel.isExtensionHidden = false
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = formatter.string(from: Date())
        
        savePanel.nameFieldStringValue = "ShadowsocksX-NG_diagnose_\(dateString)"
        
        savePanel.becomeKey()
        let result = savePanel.runModal()
        if (result.rawValue == NSFileHandlingPanelOKButton) {
            if let url = savePanel.url {
                let diagnosisText = diagnose()
                try! diagnosisText.write(to: url, atomically: false, encoding: String.Encoding.utf8)
            }
        }
    }
    
    @IBAction func showHelp(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(URL(string: "https://github.com/shadowsocks/ShadowsocksX-NG/wiki")!)
    }
    
    @IBAction func showAbout(_ sender: NSMenuItem) {
        NSApp.orderFrontStandardAboutPanel(sender);
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func updateRunningModeMenu() {
        let defaults = UserDefaults.standard
        
        if let pacURL = defaults.string(forKey: "ExternalPACURL") {
            if pacURL != "" {
                externalPACModeMenuItem.isEnabled = true
            } else {
                externalPACModeMenuItem.isEnabled = false
            }
        }

        // Update running mode state
        autoModeMenuItem.state = .off
        globalModeMenuItem.state = .off
        manualModeMenuItem.state = .off
        externalPACModeMenuItem.state = .off
        
        let mode = defaults.string(forKey: "ShadowsocksRunningMode")
        if mode == "auto" {
            autoModeMenuItem.state = .on
        } else if mode == "global" {
            globalModeMenuItem.state = .on
        } else if mode == "manual" {
            manualModeMenuItem.state = .on
        } else if mode == "externalPAC" {
            externalPACModeMenuItem.state = .on
        }
        updateStatusMenuImage()
        
        // Update selected server name
        var serverMenuText = "Servers - (No Selected)".localized
        
        let mgr = ServerProfileManager.instance
        for p in mgr.profiles {
            if mgr.activeProfileId == p.uuid {
                var profileName :String
                if !p.remark.isEmpty {
                    profileName = String(p.remark.prefix(24))
                } else {
                    profileName = p.serverHost
                }
                serverMenuText = "Servers".localized + " - \(profileName)"
                break
            }
        }
        serversMenuItem.title = serverMenuText
    }
    
    func updateStatusMenuImage() {
        let defaults = UserDefaults.standard
        let mode = defaults.string(forKey: "ShadowsocksRunningMode")
        let isOn = defaults.bool(forKey: "ShadowsocksOn")
        if isOn {
            if let m = mode {
                switch m {
                    case "auto":
                        statusItem.image = NSImage(named: "menu_p_icon")
                    case "global":
                        statusItem.image = NSImage(named: "menu_g_icon")
                    case "manual":
                        statusItem.image = NSImage(named: "menu_m_icon")
                    case "externalPAC":
                        statusItem.image = NSImage(named: "menu_e_icon")
                default: break
                }
                statusItem.image?.isTemplate = true
            }
        } else {
            statusItem.image = NSImage(named: "menu_icon_disabled")
            statusItem.image?.isTemplate = true
        }
    }
    
    func updateMainMenu() {
        let defaults = UserDefaults.standard
        let isOn = defaults.bool(forKey: "ShadowsocksOn")
        if isOn {
            runningStatusMenuItem.title = "Shadowsocks: On".localized
            runningStatusMenuItem.image = NSImage(named: "NSStatusAvailable")
            toggleRunningMenuItem.title = "Turn Shadowsocks Off".localized
            let image = NSImage(named: "menu_icon")
            statusItem.image = image
        } else {
            runningStatusMenuItem.title = "Shadowsocks: Off".localized
            toggleRunningMenuItem.title = "Turn Shadowsocks On".localized
            runningStatusMenuItem.image = NSImage(named: "NSStatusNone")
            let image = NSImage(named: "menu_icon_disabled")
            statusItem.image = image
        }
        statusItem.image?.isTemplate = true
        
        updateStatusMenuImage()
    }
    
    func updateCopyHttpProxyExportMenu() {
        let defaults = UserDefaults.standard
        let isOn = defaults.bool(forKey: "LocalHTTPOn")
        copyHttpProxyExportCmdLineMenuItem.isHidden = !isOn
    }
    
    func updateServersMenu() {
        guard let menu = serversMenuItem.submenu else { return }

        let mgr = ServerProfileManager.instance
        let profiles = mgr.profiles

        // Remove all profile menu items
        let beginIndex = menu.index(of: serverProfilesBeginSeparatorMenuItem) + 1
        let endIndex = menu.index(of: serverProfilesEndSeparatorMenuItem)
        // Remove from end to begin, so the index won't change :)
        for index in (beginIndex..<endIndex).reversed() {
            menu.removeItem(at: index)
        }

        // Insert all profile menu items
        for (i, profile) in profiles.enumerated().reversed() {
            let item = NSMenuItem()
            item.tag = i + kProfileMenuItemIndexBase
            item.title = profile.title()
            item.state = (mgr.activeProfileId == profile.uuid) ? .on : .off
            item.isEnabled = profile.isValid()
            // Use number keys for faster switch between the first 10 servers from main menu
            if i < 10 {
                var key = i + 1
                if key == 10 {
                    key = 0
                }
                item.keyEquivalent = String(key)
                item.keyEquivalentModifierMask = .init()
            }
            item.action = #selector(AppDelegate.selectServer)
            
            menu.insertItem(item, at: beginIndex)
        }

        // End separator is redundant if profile section is empty
        serverProfilesEndSeparatorMenuItem.isHidden = profiles.isEmpty
    }
    
    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        if let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue {
            if let url = URL(string: urlString) {
                NotificationCenter.default.post(
                    name: NOTIFY_FOUND_SS_URL, object: nil
                    , userInfo: [
                        "urls": [url],
                        "source": "url",
                        ])
            }
        }
    }
    
    func handleFoundSSURL(_ note: Notification) {
        let sendNotify = {
            (title: String, subtitle: String, infoText: String) in
            
            let userNote = NSUserNotification()
            userNote.title = title
            userNote.subtitle = subtitle
            userNote.informativeText = infoText
            userNote.soundName = NSUserNotificationDefaultSoundName
            
            NSUserNotificationCenter.default
                .deliver(userNote);
        }
        
        if let userInfo = (note as NSNotification).userInfo {
            let urls: [URL] = userInfo["urls"] as! [URL]
            
            let mgr = ServerProfileManager.instance
            let addCount = mgr.addServerProfileByURL(urls: urls)
            
            if addCount > 0 {
                var subtitle: String = ""
                if userInfo["source"] as! String == "qrcode" {
                    subtitle = "By scan QR Code".localized
                } else if userInfo["source"] as! String == "url" {
                    subtitle = "By handle SS URL".localized
                } else if userInfo["source"] as! String == "pasteboard" {
                    subtitle = "By import from pasteboard".localized
                }
                
                sendNotify("Add \(addCount) Shadowsocks Server Profile".localized, subtitle, "")
            } else {
                if userInfo["source"] as! String == "qrcode" {
                    sendNotify("", "", "Not found valid QRCode of shadowsocks profile".localized)
                } else if userInfo["source"] as! String == "url" {
                    sendNotify("", "", "Not found valid URL of shadowsocks profile".localized)
                }
            }
        }
    }
    
    //------------------------------------------------------------
    // NSUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: NSUserNotificationCenter
        , shouldPresent notification: NSUserNotification) -> Bool {
        return true
    }
    
    
    func makeToast(_ message: String) {
        if toastWindowCtrl != nil {
            toastWindowCtrl.close()
        }
        toastWindowCtrl = ToastWindowController(windowNibName: "ToastWindowController")
        toastWindowCtrl.message = message
        toastWindowCtrl.showWindow(self)
        //NSApp.activate(ignoringOtherApps: true)
        //toastWindowCtrl.window?.makeKeyAndOrderFront(self)
        toastWindowCtrl.fadeInHud()
    }
}

