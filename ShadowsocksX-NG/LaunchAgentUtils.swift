//
//  BGUtils.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/6.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Foundation

let SS_LOCAL_VERSION = "2.4.6"
let APP_SUPPORT_DIR = "/Library/Application Support/ShadowsocksX-NE/"
let LAUNCH_AGENT_DIR = "/Library/LaunchAgents/"
let LAUNCH_AGENT_CONF_NAME = "com.qiuyuzhou.shadowsocksX-NE.local.plist"


func getFileSHA1Sum(filepath: String) -> String {
    if let data = NSData(contentsOfFile: filepath) {
        return data.sha1()
    }
    return ""
}

// Ref: https://developer.apple.com/library/mac/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html
// Genarate the mac launch agent service plist
func generateSSLocalLauchAgentPlist() -> Bool {
    let sslocalPath = NSHomeDirectory() + APP_SUPPORT_DIR + "ss-local"
    let logFilePath = NSHomeDirectory() + "/Library/Logs/ss-local.log"
    let plistFilepath = NSHomeDirectory() + LAUNCH_AGENT_DIR + LAUNCH_AGENT_CONF_NAME
    
    let oldSha1Sum = getFileSHA1Sum(plistFilepath)
    
    let enableUdpRelay = NSUserDefaults.standardUserDefaults().boolForKey("LocalSocks5.EnableUDPRelay")
    
    var arguments = [sslocalPath, "-c", "ss-local-config.json"]
    if enableUdpRelay {
        arguments.append("-u")
    }
    
    // For a complete listing of the keys, see the launchd.plist manual page.
    let dict: NSMutableDictionary = [
        "Label": "com.qiuyuzhou.shadowsocksX-NE.local",
        "WorkingDirectory": NSHomeDirectory() + APP_SUPPORT_DIR,
        "KeepAlive": true,
        "StandardOutPath": logFilePath,
        "StandardErrorPath": logFilePath,
        "ProgramArguments": arguments,
        "EnvironmentVariables": ["DYLD_LIBRARY_PATH": NSHomeDirectory() + APP_SUPPORT_DIR]
    ]
    dict.writeToFile(plistFilepath, atomically: true)
    let Sha1Sum = getFileSHA1Sum(plistFilepath)
    if oldSha1Sum != Sha1Sum {
        return true
    } else {
        return false
    }
}

func ReloadConfSSLocal() {
    let bundle = NSBundle.mainBundle()
    let installerPath = bundle.pathForResource("reload_conf_ss_local.sh", ofType: nil)
    let task = NSTask.launchedTaskWithLaunchPath(installerPath!, arguments: [""])
    task.waitUntilExit()
    if task.terminationStatus == 0 {
        NSLog("Start ss-local succeeded.")
    } else {
        NSLog("Start ss-local failed.")
    }
}

func StartSSLocal() {
    let bundle = NSBundle.mainBundle()
    let installerPath = bundle.pathForResource("start_ss_local.sh", ofType: nil)
    let task = NSTask.launchedTaskWithLaunchPath(installerPath!, arguments: [""])
    task.waitUntilExit()
    if task.terminationStatus == 0 {
        NSLog("Start ss-local succeeded.")
    } else {
        NSLog("Start ss-local failed.")
    }
}

func StopSSLocal() {
    let bundle = NSBundle.mainBundle()
    let installerPath = bundle.pathForResource("stop_ss_local.sh", ofType: nil)
    let task = NSTask.launchedTaskWithLaunchPath(installerPath!, arguments: [""])
    task.waitUntilExit()
    if task.terminationStatus == 0 {
        NSLog("Stop ss-local succeeded.")
    } else {
        NSLog("Stop ss-local failed.")
    }
}

func InstallSSLocal() {
    let fileMgr = NSFileManager.defaultManager()
    let homeDir = NSHomeDirectory()
    let appSupportDir = homeDir+APP_SUPPORT_DIR
    if !fileMgr.fileExistsAtPath(appSupportDir + "ss-local-\(SS_LOCAL_VERSION)/ss-local")
    || !fileMgr.fileExistsAtPath(appSupportDir + "libcrypto.1.0.0.dylib") {
        let bundle = NSBundle.mainBundle()
        let installerPath = bundle.pathForResource("install_ss_local.sh", ofType: nil)
        let task = NSTask.launchedTaskWithLaunchPath(installerPath!, arguments: [""])
        task.waitUntilExit()
        if task.terminationStatus == 0 {
            NSLog("Install ss-local succeeded.")
        } else {
            NSLog("Install ss-local failed.")
        }
    }
}

func writeSSLocalConfFile(conf:[String:AnyObject]) -> Bool {
    do {
        let filepath = NSHomeDirectory() + APP_SUPPORT_DIR + "ss-local-config.json"
        let data: NSData = try NSJSONSerialization.dataWithJSONObject(conf, options: .PrettyPrinted)
        
        let oldSum = getFileSHA1Sum(filepath)
        try data.writeToFile(filepath, options: .DataWritingAtomic)
        let newSum = getFileSHA1Sum(filepath)
        
        if oldSum == newSum {
            return false
        }
        
        return true
    } catch {
        NSLog("Write ss-local file failed.")
    }
    return false
}

func removeSSLocalConfFile() {
    do {
        let filepath = NSHomeDirectory() + APP_SUPPORT_DIR + "ss-local-config.json"
        try NSFileManager.defaultManager().removeItemAtPath(filepath)
    } catch {
        
    }
}

func SyncSSLocal() {
    var changed: Bool = false
    changed = changed || generateSSLocalLauchAgentPlist()
    let mgr = ServerProfileManager()
    if mgr.activeProfileId != nil {
        changed = changed || writeSSLocalConfFile((mgr.getActiveProfile()?.toJsonConfig())!)
        
        let on = NSUserDefaults.standardUserDefaults().boolForKey("ShadowsocksOn")
        if on {
            StartSSLocal()
            ReloadConfSSLocal()
        }
    } else {
        removeSSLocalConfFile()
        StopSSLocal()
    }
    SyncPac()
}
