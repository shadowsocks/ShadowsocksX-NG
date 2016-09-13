//
//  PingTest.swift
//  ShadowsocksX-NG
//
//  Created by 秦宇航 on 16/9/12.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Foundation

class PingTest: NSObject, SimplePingDelegate {
    static let instance = PingTest(hostName: "")
    //then 写一个init函数，传入hostName来init
    var hostName = "jp10.hexiehao.pw"
    
    var pinger: SimplePing?
    var sendTimer: NSTimer?
    var dateReference: NSDate?
    
    /// Called by the table view selection delegate callback to start the ping.
    init(hostName:String) {
        self.hostName = hostName
    }
    func start() {
        
        NSLog("start ping %@",self.hostName)
        
        let pinger = SimplePing(hostName: self.hostName)
        self.pinger = pinger
        
        pinger.delegate = self
        pinger.start()
    }
    
    /// Called by the table view selection delegate callback to stop the ping.
    
    func stop() {
        NSLog("stop")
        self.pinger?.stop()
        self.pinger = nil
        
        self.sendTimer?.invalidate()
        self.sendTimer = nil
    }
    
    /// Sends a ping.
    ///
    /// Called to send a ping, both directly (as soon as the SimplePing object starts up) and
    /// via a timer (to continue sending pings periodically).
    
    func sendPing() {
        self.pinger!.sendPingWithData(nil)
    }
    
    // MARK: pinger delegate callback
    
    func simplePing(pinger: SimplePing, didStartWithAddress address: NSData) {
        NSLog("pinging %@",hostName)
        
        // Send the first ping straight away.
        
        self.sendPing()
        
        // And start a timer to send the subsequent pings.
        
        assert(self.sendTimer == nil)
        self.sendTimer = NSTimer.scheduledTimerWithTimeInterval(1.0, target: self, selector: #selector(PingTest.sendPing), userInfo: nil, repeats: true)
    }
    
    func simplePing(pinger: SimplePing, didFailWithError error: NSError) {
        NSLog("failed: %@", PingTest.shortErrorFromError(error))
        
        self.stop()
    }
    
    func simplePing(pinger: SimplePing, didSendPacket packet: NSData, sequenceNumber: UInt16) {
        NSLog("#%u sent", sequenceNumber)
        dateReference = NSDate()
    }
    
    func simplePing(pinger: SimplePing, didFailToSendPacket packet: NSData, sequenceNumber: UInt16, error: NSError) {
        NSLog("#%u send failed: %@", sequenceNumber, PingTest.shortErrorFromError(error))
    }
    
    func simplePing(pinger: SimplePing, didReceivePingResponsePacket packet: NSData, sequenceNumber: UInt16) {
        
        pinger.stop()
        
        guard let dateReference = dateReference else { return }
        
        //timeIntervalSinceDate returns seconds, so we convert to milis
        dispatch_async(dispatch_get_main_queue(), {
            let latency = NSDate().timeIntervalSinceDate(dateReference) * 1000
            NSLog("#%u received, host=%@, size=%zu, latency=%.f", sequenceNumber, self.hostName , packet.length,latency)
            let userNote = NSUserNotification()
            userNote.title = "\(self.hostName) ping \(latency)".localized
            userNote.subtitle = "Address can't not be recognized".localized
            NSUserNotificationCenter.defaultUserNotificationCenter()
                .deliverNotification(userNote)

            })
    }
    
    func simplePing(pinger: SimplePing, didReceiveUnexpectedPacket packet: NSData) {
        NSLog("unexpected packet, size=%zu", packet.length)
    }
    
    // MARK: utilities
    
    /// Returns the string representation of the supplied address.
    ///
    /// - parameter address: Contains a `(struct sockaddr)` with the address to render.
    ///
    /// - returns: A string representation of that address.
    
    static func displayAddressForAddress(address: NSData) -> String {
        var hostStr = [Int8](count: Int(NI_MAXHOST), repeatedValue: 0)
        
        let success = getnameinfo(
            UnsafePointer(address.bytes),
            socklen_t(address.length),
            &hostStr,
            socklen_t(hostStr.count),
            nil,
            0,
            NI_NUMERICHOST
            ) == 0
        let result: String
        if success {
            result = String.fromCString(hostStr)!
        } else {
            result = "?"
        }
        return result
    }
    
    /// Returns a short error string for the supplied error.
    ///
    /// - parameter error: The error to render.
    ///
    /// - returns: A short string representing that error.
    
    static func shortErrorFromError(error: NSError) -> String {
        if error.domain == kCFErrorDomainCFNetwork as String && error.code == Int(CFNetworkErrors.CFHostErrorUnknown.rawValue) {
            if let failureObj = error.userInfo[kCFGetAddrInfoFailureKey] {
                if let failureNum = failureObj as? NSNumber {
                    if failureNum.intValue != 0 {
                        let f = gai_strerror(failureNum.intValue)
                        if f != nil {
                            return String.fromCString(f)!
                        }
                    }
                }
            }
        }
        if let result = error.localizedFailureReason {
            return result
        }
        return error.localizedDescription
    }
    class func pingArray(){//hostList : [String]) -> [[String : String]]{
//        return [["apple.com":"20"],["baidu.com":"20"]]
        
        
        
        
    }
}


