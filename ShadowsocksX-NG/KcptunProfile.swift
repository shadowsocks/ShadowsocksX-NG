//
//  KcptunProfile.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 2017/1/11.
//  Copyright © 2017年 qiuyuzhou. All rights reserved.
//

import Foundation


class KcptunProfile: NSObject {
    
    var mode: String = "normal"
    
    var key: String = "it's a secrect"
    var crypt: String = "aes"
    var nocomp: Bool = true
    var datashard: uint = 10
    var parityshard: uint = 3
    
    
    public func copy(with zone: NSZone? = nil) -> Any {
        let copy = KcptunProfile()
        copy.mode = self.mode
        copy.key = self.key
        copy.crypt = self.crypt
        copy.nocomp = self.nocomp
        copy.datashard = self.datashard
        copy.parityshard = self.parityshard
        return copy;
    }
    
    func toDictionary() -> [String:AnyObject] {
        let conf: [String: AnyObject] = [
                                         "mode": self.mode as AnyObject,
                                         "key": self.key as AnyObject,
                                         "crypt": self.crypt as AnyObject,
                                         "nocomp": NSNumber(value: self.nocomp),
                                         "datashard": NSNumber(value: self.datashard),
                                         "parityshard": NSNumber(value: self.parityshard),
                                         ]
        return conf
    }
    
    static func fromDictionary(_ data:[String:Any?]) -> KcptunProfile {
        let profile = KcptunProfile()
        profile.mode = data["mode"] as! String
        profile.key = data["key"] as! String
        profile.crypt = data["crypt"] as! String
        profile.nocomp = (data["nocomp"] as! NSNumber).boolValue
        profile.datashard = uint((data["datashard"] as! NSNumber).uintValue)
        profile.parityshard = uint((data["parityshard"] as! NSNumber).uintValue)
        
        return profile
    }
    
    func toJsonConfig() -> [String: AnyObject] {
        let defaults = UserDefaults.standard
        let localHost = defaults.string(forKey: "Kcptun.LocalHost")
        let localPort = defaults.integer(forKey: "Kcptun.LocalPort")
        
        let conf: [String: AnyObject] = [
                                         "localaddr": "\(localHost):\(localPort)" as AnyObject,
                                         "mode": self.mode as AnyObject,
                                         "key": self.key as AnyObject,
                                         "crypt": self.crypt as AnyObject,
                                         "nocomp": NSNumber(value: self.nocomp),
                                         "datashard": NSNumber(value: self.datashard),
                                         "parityshard": NSNumber(value: self.parityshard),
                                         ]
        return conf
    }
}
