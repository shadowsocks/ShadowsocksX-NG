//
//  ServerProfileManager.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/6. Modified by 秦宇航 16/9/12
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Cocoa
import CloudKit

typealias DictionaryArray = [[String: Any]]

let recordId = CKRecordID(recordName: "UserDefaults")
var record = CKRecord(recordType: "UserDefaults", recordID: recordId)

let database = CKContainer.default().privateCloudDatabase

class ServerProfileManager: NSObject {
    
    static let instance:ServerProfileManager = ServerProfileManager()
    
    var profiles:[ServerProfile] = []
    var activeProfileId: String?
    
    fileprivate override init() {
        super.init()
        
        let defaults = UserDefaults.standard
        if let _profiles = defaults.array(forKey: "ServerProfiles") {
            for _profile in _profiles {
                let profile = ServerProfile.fromDictionary(_profile as! [String: Any])
                profiles.append(profile)
            }
        }
        activeProfileId = defaults.string(forKey: "ActiveServerProfileId")
        
        fetchCloudKitData()
    }
    
    func setActiveProfiledId(_ id: String) {
        activeProfileId = id
        let defaults = UserDefaults.standard
        defaults.set(id, forKey: "ActiveServerProfileId")
    }
    
    func save() {
        profiles.saveToLocal()
        profiles.saveToCloud()
        
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
    
    // MARK: - Helpers
    func profilesDictionaryArray() -> DictionaryArray {
        return profiles.filter({ $0.isValid() }).map({ $0.toDictionary() })
    }
    
    func fetchCloudKitData() {
        database.fetch(withRecordID: recordId) { (record, error) in
            if let error = error {
                print(error)
                
                // Sync to Cloud
                if !self.profiles.isEmpty {
                    self.profiles.saveToCloud()
                }
                
                return
            }
            
            guard let record = record,
                let profilesString = record["ServerProfiles"] as? String,
                let dictionaryArray = profilesString.jsonDictionaryArray(),
                !dictionaryArray.isEmpty else { return }
            
            let _profiles = dictionaryArray.map({ ServerProfile.fromDictionary($0) })
            
            if self.profiles.isEmpty || UserDefaults.standard.value(forKey: "Date") == nil {
                self.profiles = _profiles
                
                // Sync to local
                self.profiles.saveToLocal(date: record.modificationDate)
                
                return
            }
            
            if let remoteDate = record.modificationDate,
                let localDate = UserDefaults.standard.value(forKey: "Date") as? Date {
                
                // Sync latest data
                if remoteDate > localDate {
                    self.profiles = _profiles
                    self.profiles.saveToLocal(date: remoteDate)
                } else if remoteDate < localDate {
                    self.profiles.saveToCloud()
                }
            }
        }
    }
}

extension Array where Element: ServerProfile {
    func dictionaryArray() -> DictionaryArray {
        return filter({ $0.isValid() }).map({ $0.toDictionary() })
    }
    
    func saveToCloud() {
        record["ServerProfiles"] = dictionaryArray().toJSONString()
        database.save(record) { (record, error) in
            if let error = error {
                print(error)
            }
        }
    }
    
    func saveToLocal(date: Date? = Date()) {
        let _profiles: DictionaryArray = dictionaryArray()
        UserDefaults.standard.set(_profiles, forKey: "ServerProfiles")
        UserDefaults.standard.set(date, forKey: "Date")
    }
}
