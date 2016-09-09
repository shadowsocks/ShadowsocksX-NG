//
//  PingClient.swift
//  ShadowsocksX-R
//
//  Created by 称一称 on 16/9/5.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//


import Foundation

public typealias SimplePingClientCallback = (String?)->()

public class SimplePingClient: NSObject {
    static let singletonPC = SimplePingClient()

    private var resultCallback: SimplePingClientCallback?
    private var pingClinet: SimplePing?
    private var dateReference: NSDate?

    public static func pingHostname(hostname: String, andResultCallback callback: SimplePingClientCallback?) {
        singletonPC.pingHostname(hostname, andResultCallback: callback)
    }

    public func pingHostname(hostname: String, andResultCallback callback: SimplePingClientCallback?) {
        resultCallback = callback
        pingClinet = SimplePing(hostName: hostname)
        pingClinet?.delegate = self
        pingClinet?.start()
    }
}

extension SimplePingClient: SimplePingDelegate {
    public func simplePing(pinger: SimplePing, didStartWithAddress address: NSData) {
        pinger.sendPingWithData(nil)


    }

    public func simplePing(pinger: SimplePing, didFailWithError error: NSError) {
        resultCallback?(nil)
    }

    public func simplePing(pinger: SimplePing, didSendPacket packet: NSData, sequenceNumber: UInt16) {
        dateReference = NSDate()
    }

    public func simplePing(pinger: SimplePing, didFailToSendPacket packet: NSData, sequenceNumber: UInt16, error: NSError) {
        pinger.stop()
        resultCallback?(nil)
    }

    public func simplePing(pinger: SimplePing, didReceiveUnexpectedPacket packet: NSData) {
        pinger.stop()
        resultCallback?(nil)
    }

    public func simplePing(pinger: SimplePing, didReceivePingResponsePacket packet: NSData, sequenceNumber: UInt16 ){
        pinger.stop()

        guard let dateReference = dateReference else{return }

        //timeIntervalSinceDate returns seconds, so we convert to milis
        let latency = NSDate().timeIntervalSinceDate(dateReference) * 1000
        resultCallback?(String(format: "%.f", latency))
    }
}




class PingServers:NSObject{
    static let instance = PingServers()

    let SerMgr = ServerProfileManager.instance
    var fastest:String?
    var fastest_id : Int=0

    func ping(i:Int=0){
        if i == 0{
            fastest_id = 0
            fastest = nil
        }

        if i >= SerMgr.profiles.count{
            (NSApplication.sharedApplication().delegate as! AppDelegate).updateServersMenu()
            let notice = NSUserNotification()
            notice.title = "Ping测试完成！"
            notice.subtitle = "最快的是\(SerMgr.profiles[fastest_id].remark) \(SerMgr.profiles[fastest_id].serverHost) \(SerMgr.profiles[fastest_id].latency!)ms"
            NSUserNotificationCenter.defaultUserNotificationCenter().deliverNotification(notice)
            return
        }
        let host = SerMgr.profiles[i].serverHost
        SimplePingClient.pingHostname(host) { latency in
            print("-----------\(host) latency is \(latency ?? "fail")")
            self.SerMgr.profiles[i].latency = latency ?? "fail"

            if latency != nil {
                if self.fastest == nil{
                    self.fastest = latency
                    self.fastest_id = i
                }else{
                    if latency < self.fastest{
                        self.fastest = latency
                        self.fastest_id = i
                    }
                }
            }

            self.ping(i+1)
        }
    }
}





