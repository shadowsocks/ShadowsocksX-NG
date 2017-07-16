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
    var subscribesDefault : [[String: AnyObject]]
    let defaults = UserDefaults.standard
    
    fileprivate override init() {
        subscribes = []
        subscribesDefault = [[:]]
        if let subscribesDefault = defaults.array(forKey: "Subscribes") {
            for value in subscribesDefault{
                subscribes.append(Subscribe.fromDictionary(value as! [String : AnyObject]))
            }
        }
    }
    func addSubscribe(oneSubscribe: Subscribe) -> Bool {
        subscribes.append(oneSubscribe)
        defaults.set(subscribesToDefaults(data: subscribes), forKey: "Subscribes")
        return true
    }
    func deleteSubscribe(toDeleteSubscribe: Subscribe) -> Bool {
        subscribes.enumerated().forEach({ (index, oneSubscribe) -> Void in
            if(oneSubscribe.getFeed() == toDeleteSubscribe.getFeed()){
                subscribes.remove(at: index)
            }
        })
        defaults.set(subscribesToDefaults(data: subscribes), forKey: "Subscribes")
        return true
    }
    fileprivate func subscribesToDefaults(data: [Subscribe]) -> [[String: AnyObject]]{
        var ret : [[String: AnyObject]] = []
        for value in data {
            ret.append(Subscribe.toDictionary(value))
        }
        return ret
    }
    fileprivate func DefaultsToSubscribes(data:[[String: AnyObject]]) -> [Subscribe] {
        var ret : [Subscribe] = []
        for value in data{
            ret.append(Subscribe.fromDictionary(value))
        }
        return ret
    }
    func updateAllServerFromSubscribe(){
        subscribes.forEach{ value in
            value.updateServerFromFeed()
        }
    }
}
