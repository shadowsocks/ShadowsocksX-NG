//
//  ServerProfileManager.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/6.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Cocoa

class ServerProfileManager: NSObject {
    
    static let instance:ServerProfileManager = ServerProfileManager()
    
    var profiles:[ServerProfile]
    var activeProfileId: String?
    
    private override init() {
        profiles = [ServerProfile]()
        
        let defaults = NSUserDefaults.standardUserDefaults()
        if let _profiles = defaults.arrayForKey("ServerProfiles") {
            for _profile in _profiles {
                let profile = ServerProfile.fromDictionary(_profile as! [String : AnyObject])
                profiles.append(profile)
            }
        }
        activeProfileId = defaults.stringForKey("ActiveServerProfileId")
    }
    
    func setActiveProfiledId(id: String) {
        activeProfileId = id
        let defaults = NSUserDefaults.standardUserDefaults()
        defaults.setObject(id, forKey: "ActiveServerProfileId")
    }
    
    func save() {
        let defaults = NSUserDefaults.standardUserDefaults()
        var _profiles = [AnyObject]()
        for profile in profiles {
            if profile.isValid() {
                let _profile = profile.toDictionary()
                _profiles.append(_profile)
            }
        }
        defaults.setObject(_profiles, forKey: "ServerProfiles")
        
        if getActiveProfile() == nil {
            activeProfileId = nil
        }
        
        if activeProfileId != nil {
            defaults.setObject(activeProfileId, forKey: "ActiveServerProfileId")
            writeSSLocalConfFile((getActiveProfile()?.toJsonConfig())!)
        } else {
            defaults.removeObjectForKey("ActiveServerProfileId")
            removeSSLocalConfFile()
        }
    }
    
    func getActiveProfile() -> ServerProfile? {
        if let id = activeProfileId {
            for p in profiles {
                if p.uuid == id {
                    return p
                }
            }
            return nil
        } else {
            return nil
        }
    }
}
