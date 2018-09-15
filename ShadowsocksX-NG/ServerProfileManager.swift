//
//  ServerProfileManager.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/6. Modified by 秦宇航 16/9/12
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Cocoa

class ServerProfileManager: NSObject {
    
    static let instance:ServerProfileManager = ServerProfileManager()
    
    var profiles:[ServerProfile]
    var activeProfileId: String?
    
    fileprivate override init() {
        profiles = [ServerProfile]()
        
        let defaults = UserDefaults.standard
        if let _profiles = defaults.array(forKey: "ServerProfiles") {
            for _profile in _profiles {
                let profile = ServerProfile.fromDictionary(_profile as! [String: Any])
                profiles.append(profile)
            }
        }
        activeProfileId = defaults.string(forKey: "ActiveServerProfileId")
    }
    
    func setActiveProfiledId(_ id: String) {
        activeProfileId = id
        let defaults = UserDefaults.standard
        defaults.set(id, forKey: "ActiveServerProfileId")
    }
    
    func save() {
        let defaults = UserDefaults.standard
        var _profiles = [AnyObject]()
        for profile in profiles {
            if profile.isValid() {
                let _profile = profile.toDictionary()
                _profiles.append(_profile as AnyObject)
            }
        }
        defaults.set(_profiles, forKey: "ServerProfiles")
        
        if getActiveProfile() == nil {
            activeProfileId = nil
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
