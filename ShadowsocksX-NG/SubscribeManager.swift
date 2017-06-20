//
//  SubscribeManager.swift
//  ShadowsocksX-NG
//
//  Created by 秦宇航 on 2017/6/19.
//  Copyright © 2017年 qiuyuzhou. All rights reserved.
//

import Foundation

class SubscribeManager:NSObject{
    static let instance:SubscribeManager = SubscribeManager()
    
    var subscribes:[Subscribe]
    
    fileprivate override init() {
        subscribes = [Subscribe]()
        
        let defaults = UserDefaults.standard
        if let _profiles = defaults.array(forKey: "Subscribe") {
            for _profile in _profiles {
                let profile = Subscribe(initUrlString: (_profile as AnyObject).url)
                subscribes.append(profile)

            }
        }
    }
    func addSubscribe(oneSubscribe: Subscribe) -> Bool {
        subscribes.append(oneSubscribe)
        let defaults = UserDefaults.standard
        defaults.set(subscribes, forKey: "Subscribe")
        return true
    }
    func deleteSubscribe(oneSubscribe: Subscribe) -> Bool {
        return true
    }
}
