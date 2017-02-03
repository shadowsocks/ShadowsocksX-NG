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
    var hostName = "baidu.com"
    
    var pinger: SimplePing?
    var sendTimer: Timer?
    var dateReference: Date?
    
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
        self.pinger!.send(with: nil)
    }
    
    // MARK: pinger delegate callback
    
    func simplePing(_ pinger: SimplePing, didStartWithAddress address: Data) {
        NSLog("pinging %@",hostName)
        
        // Send the first ping straight away.
        
        self.sendPing()
        
        // And start a timer to send the subsequent pings.
        
        assert(self.sendTimer == nil)
        self.sendTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(PingTest.sendPing), userInfo: nil, repeats: true)
    }
    
    func simplePing(_ pinger: SimplePing, didFailWithError error: Error) {
        NSLog("failed: %@", PingTest.shortErrorFromError(error as NSError))
        
        self.stop()
    }
    
    func simplePing(_ pinger: SimplePing, didSendPacket packet: Data, sequenceNumber: UInt16) {
        NSLog("#%u sent", sequenceNumber)
        dateReference = Date()
    }
    
    func simplePing(_ pinger: SimplePing, didFailToSendPacket packet: Data, sequenceNumber: UInt16, error: Error) {
        NSLog("#%u send failed: %@", sequenceNumber, PingTest.shortErrorFromError(error as NSError))
    }
    
    func simplePing(_ pinger: SimplePing, didReceivePingResponsePacket packet: Data, sequenceNumber: UInt16) {
        
        pinger.stop()
        
        guard let dateReference = dateReference else { return }
        
        //timeIntervalSinceDate returns seconds, so we convert to milis
        DispatchQueue.main.async(execute: {
            let latency = Date().timeIntervalSince(dateReference) * 1000
            NSLog("#%u received, host=%@, size=%zu, latency=%.f", sequenceNumber, self.hostName , packet.count,latency)
            let userNote = NSUserNotification()
            userNote.title = "\(self.hostName) ping \(latency)".localized
            userNote.subtitle = "Address can't not be recognized".localized
            NSUserNotificationCenter.default
                .deliver(userNote)

            })
    }
    
    func simplePing(_ pinger: SimplePing, didReceiveUnexpectedPacket packet: Data) {
        NSLog("unexpected packet, size=%zu", packet.count)
    }
    
    // MARK: utilities
    
    /// Returns the string representation of the supplied address.
    ///
    /// - parameter address: Contains a `(struct sockaddr)` with the address to render.
    ///
    /// - returns: A string representation of that address.
    
    static func displayAddressForAddress(_ address: Data) -> String {
        var hostStr = [Int8](repeating: 0, count: Int(NI_MAXHOST))
        
        let success = getnameinfo(
            (address as NSData).bytes.bindMemory(to: sockaddr.self, capacity: address.count),
            socklen_t(address.count),
            &hostStr,
            socklen_t(hostStr.count),
            nil,
            0,
            NI_NUMERICHOST
            ) == 0
        let result: String
        if success {
            result = String(cString: hostStr)
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
    
    static func shortErrorFromError(_ error: NSError) -> String {
        if error.domain == kCFErrorDomainCFNetwork as String && error.code == Int(CFNetworkErrors.cfHostErrorUnknown.rawValue) {
            if let failureObj = error.userInfo[kCFGetAddrInfoFailureKey as AnyHashable] {
                if let failureNum = failureObj as? NSNumber {
                    if failureNum.int32Value != 0 {
                        let f = gai_strerror(failureNum.int32Value)
                        if f != nil {
                            return String(cString: f!)
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


