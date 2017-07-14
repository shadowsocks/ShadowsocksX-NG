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
    let defaults = UserDefaults.standard
    
    fileprivate override init() {
        subscribes = defaults.array(forKey: "Subscribes") as! [Subscribe]
    }
    func addSubscribe(oneSubscribe: Subscribe) -> Bool {
        subscribes.append(oneSubscribe)
        defaults.set(subscribes, forKey: "Subscribes")
        return true
    }
    func deleteSubscribe(toDeleteSubscribe: Subscribe) -> Bool {
        subscribes.enumerated().forEach({ (index, oneSubscribe) -> Void in
            if(oneSubscribe.getFeed() == toDeleteSubscribe.getFeed()){
                subscribes.remove(at: index)
            }
        })
        defaults.set(subscribes, forKey: "Subscribes")
        return true
    }
    func updateAllServerFromSubscribe(){
        
    }
}
