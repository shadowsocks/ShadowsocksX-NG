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
    var isActive = true
    var maxCount = -1 // -1 is not limited
    var groupName = ""
    var token = ""
    var cache = ""
    
    var profileMgr: ServerProfileManager!
    
    init(initUrlString:String, initGroupName: String, initToken: String, initMaxCount: Int){
        super.init()
        subscribeFeed = initUrlString
        groupName = initGroupName
        token = initToken
    
        if initMaxCount == 0 {
            setMaxCount()
        }
        else {
            maxCount = initMaxCount
        }
        profileMgr = ServerProfileManager.instance
    }
    func getFeed() -> String{
        return subscribeFeed
    }
    func setFeed(newFeed: String){
        subscribeFeed = newFeed
    }
    func diactivateSubscribe(){
        isActive = false
    }
    func activateSubscribe(){
        isActive = true
    }
    func setGroupName(newGroupName: String) -> Bool {
        groupName = newGroupName
        return true
    }
    func getGroupName() -> String {
        return groupName
    }
    func getMaxCount() -> Int {
        return maxCount
    }
    static func fromDictionary(_ data:[String:AnyObject]) -> Subscribe {
        var feed:String = ""
        var group:String = ""
        var token:String = ""
        var maxCount:Int = -1
        for (key, value) in data {
            switch key {
            case "feed":
                feed = value as! String
            case "group":
                group = value as! String
            case "token":
                token = value as! String
            case "maxCount":
                maxCount = value as! Int
            default:
                print("")
            }
        }
        return Subscribe.init(initUrlString: feed, initGroupName: group, initToken: token, initMaxCount: maxCount)
    }
    static func toDictionary(_ data: Subscribe) -> [String: AnyObject] {
        var ret : [String: AnyObject] = [:]
        ret["feed"] = data.subscribeFeed as AnyObject
        ret["group"] = data.groupName as AnyObject
        ret["token"] = data.token as AnyObject
        ret["maxCount"] = data.maxCount as AnyObject
        return ret
    }
    fileprivate func sendRequest(url: String, options: Any, callback: @escaping (String) -> Void) {
        let headers: HTTPHeaders = [
            //            "Authorization": "Basic U2hhZG93c29ja1gtTkctUg==",
            //            "Accept": "application/json",
            "token": self.token,
            "User-Agent": "ShadowsocksX-NG-R"
        ]
        
        Alamofire.request(url, headers: headers)
            .responseString{
                response in
                if response.result.isSuccess {
                    callback(response.result.value!)
                }
                else{
                    callback("")
                    self.pushNotification(title: "请求失败", subtitle: "", info: "发送到\(url)的请求失败，请检查您的网络")
                }
        }
    }
    func setMaxCount() {
        
        func getMaxFromRes(resString: String) {
            let maxCountReg = "MAX=[0-9]+"
            let decodeRes = decode64(resString)!
            let range = decodeRes.range(of: maxCountReg, options: .regularExpression)
            if range != nil {
                let result = decodeRes.substring(with:range!)
                self.maxCount = Int(result.replacingOccurrences(of: "MAX=", with: ""))!
            }
            else{
                self.maxCount = -1
            }
        }
        
        if cache != "" {
            return getMaxFromRes(resString: cache)
        }
        sendRequest(url: self.subscribeFeed, options: "", callback: { resString in
            if resString == "" {return}
            getMaxFromRes(resString: resString)
            self.cache = resString
        })
    }
    func updateServerFromFeed(){
        
        func updateServerHandler(resString: String) {
            let decodeRes = decode64(resString)!
            let ssrregexp = "ssr://([A-Za-z0-9_-]+)"
            let urls = splitor(url: decodeRes, regexp: ssrregexp)
            // hold if user fill a maxCount larger then server return
            // Should push a notification about it and correct the user filled maxCOunt?
            let maxN = (self.maxCount > urls.count) ? urls.count : (self.maxCount == -1) ? urls.count: self.maxCount
            // TODO change the loop into random pick
            for index in 0..<maxN {
                
                let profielDict = ParseAppURLSchemes(URL(string: urls[index]))//ParseSSURL(url)
                if let profielDict = profielDict {
                    let profile = ServerProfile.fromDictionary(profielDict as [String : AnyObject])
                    let (dupResult, _) = self.profileMgr.isDuplicated(profile: profile)
                    let (existResult, existIndex) = self.profileMgr.isExisted(profile: profile)
                    if dupResult {
                        continue
                    }
                    if existResult {
                        self.profileMgr.profiles.replaceSubrange(Range(existIndex..<existIndex + 1), with: [profile])
                        continue
                    }
                    self.profileMgr.profiles.append(profile)
                }
            }
            self.profileMgr.save()
            pushNotification(title: "成功更新订阅", subtitle: "", info: "更新来自\(subscribeFeed)的订阅")
            (NSApplication.shared().delegate as! AppDelegate).updateServersMenu()
        }
        
        if (!isActive){ return }
//        if cache != "" {
//            return updateServerHandler(resString: cache)
//        }
        sendRequest(url: self.subscribeFeed, options: "", callback: { resString in
            if resString == "" {return}
            updateServerHandler(resString: resString)
            self.cache = resString
        })
    }
    func feedValidator() -> Bool{
        // is the right format
        return subscribeFeed != "" && groupName != ""
    }
    fileprivate func pushNotification(title: String, subtitle: String, info: String){
        let userNote = NSUserNotification()
        userNote.title = title
        userNote.subtitle = subtitle
        userNote.informativeText = info
        userNote.soundName = NSUserNotificationDefaultSoundName
        
        NSUserNotificationCenter.default
            .deliver(userNote);
    }
    class func isSame(source: Subscribe, target: Subscribe) -> Bool {
        return source.subscribeFeed == target.subscribeFeed && source.token == target.token && source.maxCount == target.maxCount
    }
    func isExist(_ target: Subscribe) -> Bool {
        return self.subscribeFeed == target.subscribeFeed
    }
}
