//
//  MonitorTask.swift
//  Up&Down
//
//  Created by 郭佳哲 on 6/3/16.
//  Copyright © 2016 郭佳哲. All rights reserved.
//

import Foundation

open class NetWorkMonitor: NSObject {
    let statusItemView: StatusItemView

    var thread:Thread?
    var timer:Timer?

    init(statusItemView view: StatusItemView) {
        statusItemView = view
    }
    
    func start() {
        thread = Thread(target: self, selector: #selector(startUpdateTimer), object: nil)
        thread?.start()
        statusItemView.showSpeed = true
    }
    
    func startUpdateTimer() {
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(updateNetWorkData), userInfo: nil, repeats: true)
        if #available(OSX 10.12, *){
            
            let alertView = NSAlert()
            alertView.messageText = "网速显示不支持 macOS 10.12 Sierra!"
            alertView.informativeText = "因为 macOS 10.12 Sierra ABI 不稳定，因此暂时移除网速功能"
            alertView.addButton(withTitle: "取消网速显示")
            _ = DispatchQueue.main.sync(execute: { Void in
                alertView.runModal()
            })
            stop()
//            NSRunLoop.currentRunLoop().run()
//            CFRunLoopRun()
            
        } else {
            RunLoop.current.add(timer!, forMode: RunLoopMode.commonModes)
            RunLoop.current.run()
            print(RunLoop.current.getCFRunLoop())
        }
    }

    func stop(){
        thread?.cancel()
        statusItemView.showSpeed = false
        
    }

    
    func updateNetWorkData() {

        if Thread.current.isCancelled{
            timer?.invalidate()
            timer = nil
            thread = nil
            Thread.exit()

        }

        let task = Process()
        task.launchPath = "/usr/bin/sar"
        task.arguments = ["-n", "DEV", "1"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        task.launch()
        task.waitUntilExit()
        
        let status = task.terminationStatus
        if status == 0 {
            //            print("Task succeeded.")
            let fileHandle = pipe.fileHandleForReading
            let data = fileHandle.readDataToEndOfFile()
            
            var string = String(data: data, encoding: String.Encoding.utf8)
            string = string?.substring(from: (string?.range(of: "Aver")?.lowerBound)!)
            handleNetWorkData(string!)
        } else {
            print("Task failed.")
        }
    }
    
    /*
     23:18:25    IFACE    Ipkts/s      Ibytes/s     Opkts/s      Obytes/s
     
     
     23:18:26    lo0            0             0           0             0
     23:18:26    gif0           0             0           0             0
     23:18:26    stf0           0             0           0             0
     23:18:26    en0            0             0           0             0
     23:18:26    en1            0             0           0             0
     23:18:26    en2            0             0           0             0
     23:18:26    p2p0           0             0           0             0
     23:18:26    awdl0          0             0           0             0
     23:18:26    bridge0        0             0           0             0
     23:18:26    en4            0             0           0             0
     Average:   lo0            0             0           0             0
     Average:   gif0           0             0           0             0
     Average:   stf0           0             0           0             0
     Average:   en0            0             0           0             0
     Average:   en1            0             0           0             0
     Average:   en2            0             0           0             0
     Average:   p2p0           0             0           0             0
     Average:   awdl0          0             0           0             0
     Average:   bridge0        0             0           0             0
     Average:   en4            0             0           0             0
     */
    func handleNetWorkData(_ string: String) {
        //        print(string)
        let pattern = "en\\w+\\s+(\\d+)\\s+(\\d+)\\s+(\\d+)\\s+(\\d+)"
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: NSRegularExpression.Options.caseInsensitive)
            let results = regex.matches(in: string, options: NSRegularExpression.MatchingOptions(rawValue: 0), range: NSMakeRange(0, string.characters.count))
            var upRate: Float = 0.00
            var downRate: Float = 0.00
            for result in results {
                downRate += Float((string as NSString).substring(with: result.rangeAt(2)))!
                upRate += Float((string as NSString).substring(with: result.rangeAt(4)))!
            }
            statusItemView.setRateData(up: upRate, down: downRate)
        }
        catch {}
    }

}
