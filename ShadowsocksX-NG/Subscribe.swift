//
//  Subscribe.swift
//  ShadowsocksX-NG
//
//  Created by 秦宇航 on 2017/6/15.
//  Copyright © 2017年 qiuyuzhou. All rights reserved.
//

import Foundation
import Alamofire

class Subscribe: NSObject{
    
    var subscribeFeed = ""
    var profileMgr: ServerProfileManager!
    
    init(initUrlString:String){
        subscribeFeed = initUrlString
    }
    func getFeed() -> String{
        return subscribeFeed
    }
    func setFeed(newFeed: String){
        subscribeFeed = newFeed
    }
    func updateServerFromFeed(){
        Alamofire.request(subscribeFeed)
            .responseString {
                response in
                if response.result.isSuccess {
                    if let v = response.result.value {
                        print(v)
                        let profile = ServerProfile()
                        profile.remark = "New Server".localized
                        self.profileMgr.profiles.append(profile)
                        self.profileMgr.save()
                    }
                }
                else{
                    // res failed
                    print(response.result)
                }
        }
    }
    func feedValidator() -> Bool{
        // is the right format
        return true
    }
    fileprivate func pushNotification(){
        
    }
    fileprivate func isExisted() -> Bool{
        // using to url judge
        // if existed update
        return false
    }
    fileprivate func isDuplicated() -> Bool{
        // if duplicated skip
        return false
    }
}
