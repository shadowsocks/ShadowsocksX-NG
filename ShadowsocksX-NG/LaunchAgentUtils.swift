//
//  BGUtils.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/6.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Foundation

let SS_LOCAL_VERSION = "3.2.5"
let KCPTUN_CLIENT_VERSION = "v20190905_1"
let V2RAY_PLUGIN_VERSION = "1.2.0"
let PRIVOXY_VERSION = "3.0.26.static"
let SIMPLE_OBFS_VERSION = "0.0.5_1"
let APP_SUPPORT_DIR = "/Library/Application Support/ShadowsocksX-NG/"
let USER_CONFIG_DIR = "/.ShadowsocksX-NG/"
let LAUNCH_AGENT_DIR = "/Library/LaunchAgents/"
let LAUNCH_AGENT_CONF_SSLOCAL_NAME = "com.qiuyuzhou.shadowsocksX-NG.local.plist"
let LAUNCH_AGENT_CONF_PRIVOXY_NAME = "com.qiuyuzhou.shadowsocksX-NG.http.plist"
let LAUNCH_AGENT_CONF_KCPTUN_NAME = "com.qiuyuzhou.shadowsocksX-NG.kcptun.plist"


func getFileSHA1Sum(_ filepath: String) -> String {
    if let data = try? Data(contentsOf: URL(fileURLWithPath: filepath)) {
        return data.sha1()
    }
    return ""
}

// Ref: https://developer.apple.com/library/mac/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html
// Genarate the mac launch agent service plist

//  MARK: sslocal

func generateSSLocalLauchAgentPlist() -> Bool {
    let sslocalPath = NSHomeDirectory() + APP_SUPPORT_DIR + "ss-local-latest/ss-local"
    let logFilePath = NSHomeDirectory() + "/Library/Logs/ss-local.log"
    let launchAgentDirPath = NSHomeDirectory() + LAUNCH_AGENT_DIR
    let plistFilepath = launchAgentDirPath + LAUNCH_AGENT_CONF_SSLOCAL_NAME
    
    // Ensure launch agent directory is existed.
    let fileMgr = FileManager.default
    if !fileMgr.fileExists(atPath: launchAgentDirPath) {
        try! fileMgr.createDirectory(atPath: launchAgentDirPath, withIntermediateDirectories: true, attributes: nil)
    }
    
    let oldSha1Sum = getFileSHA1Sum(plistFilepath)
    
    let defaults = UserDefaults.standard
    let enableUdpRelay = defaults.bool(forKey: "LocalSocks5.EnableUDPRelay")
    let enableVerboseMode = defaults.bool(forKey: "LocalSocks5.EnableVerboseMode")
    
    var arguments = [sslocalPath, "-c", "ss-local-config.json", "--fast-open"]
    if enableUdpRelay {
        arguments.append("-u")
    }
    if enableVerboseMode {
        arguments.append("-v")
    }
    arguments.append("--reuse-port")
    
    // For a complete listing of the keys, see the launchd.plist manual page.
    let dyld_library_paths = [
        NSHomeDirectory() + APP_SUPPORT_DIR + "ss-local-latest/",
        NSHomeDirectory() + APP_SUPPORT_DIR + "plugins/",
        ]
    
    let dict: NSMutableDictionary = [
        "Label": "com.qiuyuzhou.shadowsocksX-NG.local",
        "WorkingDirectory": NSHomeDirectory() + APP_SUPPORT_DIR,
        "StandardOutPath": logFilePath,
        "StandardErrorPath": logFilePath,
        "ProgramArguments": arguments,
        "EnvironmentVariables": ["DYLD_LIBRARY_PATH": dyld_library_paths.joined(separator: ":")]
    ]
    dict.write(toFile: plistFilepath, atomically: true)
    let Sha1Sum = getFileSHA1Sum(plistFilepath)
    if oldSha1Sum != Sha1Sum {
        NSLog("generateSSLocalLauchAgentPlist - File has been changed.")
        return true
    } else {
        NSLog("generateSSLocalLauchAgentPlist - File has not been changed.")
        return false
    }
}

func StartSSLocal() {
    let bundle = Bundle.main
    let installerPath = bundle.path(forResource: "start_ss_local.sh", ofType: nil)
    let task = Process.launchedProcess(launchPath: installerPath!, arguments: [""])
    task.waitUntilExit()
    if task.terminationStatus == 0 {
        NSLog("Start ss-local succeeded.")
    } else {
        NSLog("Start ss-local failed.")
    }
}

func StopSSLocal() {
    let bundle = Bundle.main
    let installerPath = bundle.path(forResource: "stop_ss_local.sh", ofType: nil)
    let task = Process.launchedProcess(launchPath: installerPath!, arguments: [""])
    task.waitUntilExit()
    if task.terminationStatus == 0 {
        NSLog("Stop ss-local succeeded.")
    } else {
        NSLog("Stop ss-local failed.")
    }
}

func InstallSSLocal() {
    let fileMgr = FileManager.default
    let homeDir = NSHomeDirectory()
    let appSupportDir = homeDir+APP_SUPPORT_DIR
    if !fileMgr.fileExists(atPath: appSupportDir + "ss-local-\(SS_LOCAL_VERSION)/ss-local")
       || !fileMgr.fileExists(atPath: appSupportDir + "ss-local-\(SS_LOCAL_VERSION)/libmbedcrypto.0.dylib") {
        let bundle = Bundle.main
        let installerPath = bundle.path(forResource: "install_ss_local.sh", ofType: nil)
        let task = Process.launchedProcess(launchPath: installerPath!, arguments: [""])
        task.waitUntilExit()
        if task.terminationStatus == 0 {
            NSLog("Install ss-local succeeded.")
        } else {
            NSLog("Install ss-local failed.")
        }
    }
}

func writeSSLocalConfFile(_ conf:[String:AnyObject]) -> Bool {
    do {
        let filepath = NSHomeDirectory() + APP_SUPPORT_DIR + "ss-local-config.json"
        var data: Data = try JSONSerialization.data(withJSONObject: conf, options: .prettyPrinted)

        // https://github.com/shadowsocks/ShadowsocksX-NG/issues/1104
        // This is NSJSONSerialization.dataWithJSONObject that likes to insert additional backslashes.
        // Escaped forward slashes is also valid json.
        // Workaround:
        let s = String(data:data, encoding: .utf8)!
        data = s.replacingOccurrences(of: "\\/", with: "/").data(using: .utf8)!
        
        let oldSum = getFileSHA1Sum(filepath)
        try data.write(to: URL(fileURLWithPath: filepath), options: .atomic)
        let newSum = data.sha1()
        
        if oldSum == newSum {
            NSLog("writeSSLocalConfFile - File has not been changed.")
            return false
        }
        
        NSLog("writeSSLocalConfFile - File has been changed.")
        return true
    } catch {
        NSLog("Write ss-local file failed.")
    }
    return false
}

func removeSSLocalConfFile() {
    do {
        let filepath = NSHomeDirectory() + APP_SUPPORT_DIR + "ss-local-config.json"
        try FileManager.default.removeItem(atPath: filepath)
    } catch {
        
    }
}

func SyncSSLocal() {
    var changed: Bool = false
    changed = changed || generateSSLocalLauchAgentPlist()
    let mgr = ServerProfileManager.instance
    if mgr.activeProfileId != nil {
        if let profile = mgr.getActiveProfile() {
            changed = changed || writeSSLocalConfFile((profile.toJsonConfig()))
        }
        
        let on = UserDefaults.standard.bool(forKey: "ShadowsocksOn")
        if on {
            if changed {
                StopSSLocal()
                DispatchQueue.main.asyncAfter(
                    deadline: DispatchTime.now() + DispatchTimeInterval.seconds(1),
                    execute: {
                        () in
                        StartSSLocal()
                })
            } else {
                StartSSLocal()
            }
        } else {
            StopSSLocal()
        }
    } else {
        removeSSLocalConfFile()
        StopSSLocal()
    }
    SyncPac()
    SyncPrivoxy()
}

// --------------------------------------------------------------------------------
//  MARK: simple-obfs

func InstallSimpleObfs() {
    let fileMgr = FileManager.default
    let homeDir = NSHomeDirectory()
    let appSupportDir = homeDir + APP_SUPPORT_DIR
    if !fileMgr.fileExists(atPath: appSupportDir + "simple-obfs-\(SIMPLE_OBFS_VERSION)/obfs-local")
        || !fileMgr.fileExists(atPath: appSupportDir + "plugins/obfs-local") {
        let bundle = Bundle.main
        let installerPath = bundle.path(forResource: "install_simple_obfs.sh", ofType: nil)
        let task = Process.launchedProcess(launchPath: "/bin/sh", arguments: [installerPath!])
        task.waitUntilExit()
        if task.terminationStatus == 0 {
            NSLog("Install simple-obfs succeeded.")
        } else {
            NSLog("Install simple-obfs failed.")
        }
    }
}

// --------------------------------------------------------------------------------
//  MARK: kcptun

func InstallKcptun() {
    let fileMgr = FileManager.default
    let homeDir = NSHomeDirectory()
    let appSupportDir = homeDir+APP_SUPPORT_DIR
    if !fileMgr.fileExists(atPath: appSupportDir + "kcptun_\(KCPTUN_CLIENT_VERSION)/client") {
        let bundle = Bundle.main
        let installerPath = bundle.path(forResource: "install_kcptun", ofType: "sh")
        let task = Process.launchedProcess(launchPath: "/bin/sh", arguments: [installerPath!])
        task.waitUntilExit()
        if task.terminationStatus == 0 {
            NSLog("Install kcptun succeeded.")
        } else {
            NSLog("Install kcptun failed.")
        }
    }
}

// --------------------------------------------------------------------------------
//  MARK: v2ray-plugin

func InstallV2rayPlugin() {
    let fileMgr = FileManager.default
    let homeDir = NSHomeDirectory()
    let appSupportDir = homeDir+APP_SUPPORT_DIR
    if !fileMgr.fileExists(atPath: appSupportDir + "v2ray-plugin_\(V2RAY_PLUGIN_VERSION)/v2ray-plugin") {
        let bundle = Bundle.main
        let installerPath = bundle.path(forResource: "install_v2ray_plugin", ofType: "sh")
        let task = Process.launchedProcess(launchPath: "/bin/sh", arguments: [installerPath!])
        task.waitUntilExit()
        if task.terminationStatus == 0 {
            NSLog("Install v2ray-plugin succeeded.")
        } else {
            NSLog("Install v2ray-plugin failed.")
        }
    }
}

// --------------------------------------------------------------------------------
//  MARK: privoxy

func generatePrivoxyLauchAgentPlist() -> Bool {
    let privoxyPath = NSHomeDirectory() + APP_SUPPORT_DIR + "privoxy"
    let logFilePath = NSHomeDirectory() + "/Library/Logs/privoxy.log"
    let launchAgentDirPath = NSHomeDirectory() + LAUNCH_AGENT_DIR
    let plistFilepath = launchAgentDirPath + LAUNCH_AGENT_CONF_PRIVOXY_NAME
    
    // Ensure launch agent directory is existed.
    let fileMgr = FileManager.default
    if !fileMgr.fileExists(atPath: launchAgentDirPath) {
        try! fileMgr.createDirectory(atPath: launchAgentDirPath, withIntermediateDirectories: true, attributes: nil)
    }
    
    let oldSha1Sum = getFileSHA1Sum(plistFilepath)
    
    let arguments = [privoxyPath, "--no-daemon", "privoxy.config"]
    
    // For a complete listing of the keys, see the launchd.plist manual page.
    let dict: NSMutableDictionary = [
        "Label": "com.qiuyuzhou.shadowsocksX-NG.http",
        "WorkingDirectory": NSHomeDirectory() + APP_SUPPORT_DIR,
        "StandardOutPath": logFilePath,
        "StandardErrorPath": logFilePath,
        "ProgramArguments": arguments
    ]
    dict.write(toFile: plistFilepath, atomically: true)
    let Sha1Sum = getFileSHA1Sum(plistFilepath)
    if oldSha1Sum != Sha1Sum {
        return true
    } else {
        return false
    }
}

func StartPrivoxy() {
    let bundle = Bundle.main
    let installerPath = bundle.path(forResource: "start_privoxy.sh", ofType: nil)
    let task = Process.launchedProcess(launchPath: installerPath!, arguments: [""])
    task.waitUntilExit()
    if task.terminationStatus == 0 {
        NSLog("Start privoxy succeeded.")
    } else {
        NSLog("Start privoxy failed.")
    }
}

func StopPrivoxy() {
    let bundle = Bundle.main
    let installerPath = bundle.path(forResource: "stop_privoxy.sh", ofType: nil)
    let task = Process.launchedProcess(launchPath: installerPath!, arguments: [""])
    task.waitUntilExit()
    if task.terminationStatus == 0 {
        NSLog("Stop privoxy succeeded.")
    } else {
        NSLog("Stop privoxy failed.")
    }
}

func InstallPrivoxy() {
    let fileMgr = FileManager.default
    let homeDir = NSHomeDirectory()
    let appSupportDir = homeDir+APP_SUPPORT_DIR
    if !fileMgr.fileExists(atPath: appSupportDir + "privoxy-\(PRIVOXY_VERSION)/privoxy") {
        let bundle = Bundle.main
        let installerPath = bundle.path(forResource: "install_privoxy.sh", ofType: nil)
        let task = Process.launchedProcess(launchPath: installerPath!, arguments: [""])
        task.waitUntilExit()
        if task.terminationStatus == 0 {
            NSLog("Install privoxy succeeded.")
        } else {
            NSLog("Install privoxy failed.")
        }
    }
    
    let userConfigDir = homeDir + USER_CONFIG_DIR
    // Make dir: '~/.ShadowsocksX-NG'
    if !fileMgr.fileExists(atPath: userConfigDir) {
        try! fileMgr.createDirectory(atPath: userConfigDir
        , withIntermediateDirectories: true, attributes: nil)
    }

    // Install empty `user-privoxy.config` file.
    let userConfigPath = userConfigDir + "user-privoxy.config"
    if !fileMgr.fileExists(atPath: userConfigPath) {
        let srcPath = Bundle.main.path(forResource: "user-privoxy", ofType: "config")!
        try! fileMgr.copyItem(atPath: srcPath, toPath: userConfigPath)
    }
}

func writePrivoxyConfFile() -> Bool {
    do {
        let defaults = UserDefaults.standard
        let bundle = Bundle.main
        let templatePath = bundle.path(forResource: "privoxy.template.config", ofType: nil)
        
        // Read template file
        var template = try String(contentsOfFile: templatePath!, encoding: .utf8)
        
        template = template.replacingOccurrences(of: "{http}", with: defaults.string(forKey: "LocalHTTP.ListenAddress")! + ":" + String(defaults.integer(forKey: "LocalHTTP.ListenPort")))
        template = template.replacingOccurrences(of: "{socks5}", with: defaults.string(forKey: "LocalSocks5.ListenAddress")! + ":" + String(defaults.integer(forKey: "LocalSocks5.ListenPort")))
        
        // Append the user config file to the end
        let userConfigPath = NSHomeDirectory() + USER_CONFIG_DIR + "user-privoxy.config"
        let userConfig = try String(contentsOfFile: userConfigPath, encoding: .utf8)
        template.append(contentsOf: userConfig)
        
        // Write to file
        let data = template.data(using: .utf8)
        let filepath = NSHomeDirectory() + APP_SUPPORT_DIR + "privoxy.config"
        
        let oldSum = getFileSHA1Sum(filepath)
        try data?.write(to: URL(fileURLWithPath: filepath), options: .atomic)
        let newSum = getFileSHA1Sum(filepath)
        
        if oldSum == newSum {
            return false
        }
        
        return true
    } catch {
        NSLog("Write privoxy file failed.")
    }
    return false
}

func removePrivoxyConfFile() {
    do {
        let filepath = NSHomeDirectory() + APP_SUPPORT_DIR + "privoxy.config"
        try FileManager.default.removeItem(atPath: filepath)
    } catch {
        
    }
}

func SyncPrivoxy() {
    var changed: Bool = false
    changed = changed || generatePrivoxyLauchAgentPlist()
    let mgr = ServerProfileManager.instance
    if mgr.activeProfileId != nil {
        changed = changed || writePrivoxyConfFile()
        
        let on = UserDefaults.standard.bool(forKey: "LocalHTTPOn")
        if on {
            if changed {
                StopPrivoxy()
                DispatchQueue.main.asyncAfter(
                    deadline: DispatchTime.now() + DispatchTimeInterval.seconds(1),
                    execute: {
                        () in
                        StartPrivoxy()
                })
            } else {
                StartPrivoxy()
            }
        } else {
            StopPrivoxy()
        }
    } else {
        removePrivoxyConfFile()
        StopPrivoxy()
    }
}
