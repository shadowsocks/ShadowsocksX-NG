//
//  KcptunProfile.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 2017/1/11.
//  Copyright © 2017年 qiuyuzhou. All rights reserved.
//

import Foundation


class KcptunProfile: NSObject, NSCopying {
    
    var mode: String = "fast"
    
    var key: String = "it's a secrect"
    var crypt: String = "aes"
    var nocomp: Bool = false
    var datashard: uint = 10
    var parityshard: uint = 3
    var mtu: uint = 1350
    var arguments: String = ""
    
    
    public func copy(with zone: NSZone? = nil) -> Any {
        let copy = KcptunProfile()
        copy.mode = self.mode
        copy.key = self.key
        copy.crypt = self.crypt
        copy.nocomp = self.nocomp
        copy.datashard = self.datashard
        copy.parityshard = self.parityshard
        copy.mtu = self.mtu
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
                                         "mtu": NSNumber(value: self.mtu),
                                         "arguments": self.arguments as AnyObject,
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
        if let v = data["mtu"] as? NSNumber {
            profile.mtu = uint(v.uintValue)
        }
        if let arguments = data["arguments"] as? String {
            profile.arguments = arguments
        }
        
        return profile
    }
    
    func toJsonConfig() -> [String: AnyObject] {
        let defaults = UserDefaults.standard
        let localHost = defaults.string(forKey: "Kcptun.LocalHost")! as String
        let localPort = defaults.integer(forKey: "Kcptun.LocalPort")
        let connNum = defaults.integer(forKey: "Kcptun.Conn")
        
        let conf: [String: AnyObject] = [
                                         "localaddr": "\(localHost):\(localPort)" as AnyObject,
                                         "mode": self.mode as AnyObject,
                                         "key": self.key as AnyObject,
                                         "crypt": self.crypt as AnyObject,
                                         "nocomp": NSNumber(value: self.nocomp),
                                         "datashard": NSNumber(value: self.datashard),
                                         "parityshard": NSNumber(value: self.parityshard),
                                         "mtu": NSNumber(value: self.mtu),
                                         "conn": NSNumber(value: connNum),
                                         ]
        return conf
    }
    
    func urlQueryItems() -> [URLQueryItem] {
        return [
            URLQueryItem(name: "mode", value: mode),
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "crypt", value: crypt),
            URLQueryItem(name: "datashard", value: "\(datashard)"),
            URLQueryItem(name: "parityshard", value: "\(parityshard)"),
            URLQueryItem(name: "nocomp", value: nocomp.description),
            URLQueryItem(name: "mtu", value: "\(mtu)"),
            URLQueryItem(name: "arguments", value: arguments),
        ]
    }
    
    func loadUrlQueryItems(items: [URLQueryItem]) {
        for item in items {
            switch item.name {
            case "mode":
                if let v = item.value {
                    mode = v
                }
            case "key":
                if let v = item.value {
                    key = v
                }
            case "crypt":
                if let v = item.value {
                    crypt = v
                }
            case "datashard":
                if let v = item.value {
                    if let vv = uint(v) {
                        datashard = vv
                    }
                }
            case "parityshard":
                if let v = item.value {
                    if let vv = uint(v) {
                        parityshard = vv
                    }
                }
            case "nocomp":
                if let v = item.value {
                    if let vv = Bool(v) {
                        nocomp = vv
                    }
                }
            case "mtu":
                if let v = item.value {
                    if let vv = uint(v) {
                        mtu = vv
                    }
                }
            case "arguments":
                if let v = item.value {
                    arguments = v
                }
            default:
                continue
            }
        }
    }
}
