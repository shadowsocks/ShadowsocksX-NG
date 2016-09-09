//
//  MonitorTask.swift
//  Up&Down
//
//  Created by 郭佳哲 on 6/3/16.
//  Copyright © 2016 郭佳哲. All rights reserved.
//

import Foundation

public class NetWorkMonitor: NSObject {
    let statusItemView: StatusItemView

    var thread:NSThread?
    var timer:NSTimer?

    init(statusItemView view: StatusItemView) {
        statusItemView = view
    }
    
    func start() {
        thread = NSThread(target: self, selector: #selector(startUpdateTimer), object: nil)
        thread?.start()
        statusItemView.showSpeed = true
    }
    
    func startUpdateTimer() {
        timer = NSTimer.scheduledTimerWithTimeInterval(1, target: self, selector: #selector(updateNetWorkData), userInfo: nil, repeats: true)
        NSRunLoop.currentRunLoop().run()
    }

    func stop(){
        thread?.cancel()
        statusItemView.showSpeed = false
        
    }

    
    func updateNetWorkData() {

        if NSThread.currentThread().cancelled{
            timer?.invalidate()
            timer = nil
            thread = nil
            NSThread.exit()

        }

        let task = NSTask()
        task.launchPath = "/usr/bin/sar"
        task.arguments = ["-n", "DEV", "1"]
        
        let pipe = NSPipe()
        task.standardOutput = pipe
        
        task.launch()
        task.waitUntilExit()
        
        let status = task.terminationStatus
        if status == 0 {
            //            print("Task succeeded.")
            let fileHandle = pipe.fileHandleForReading
            let data = fileHandle.readDataToEndOfFile()
            
            var string = String(data: data, encoding: NSUTF8StringEncoding)
            string = string?.substringFromIndex((string?.rangeOfString("Aver")?.startIndex)!)
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
    func handleNetWorkData(string: String) {
        //        print(string)
        let pattern = "en\\w+\\s+(\\d+)\\s+(\\d+)\\s+(\\d+)\\s+(\\d+)"
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: NSRegularExpressionOptions.CaseInsensitive)
            let results = regex.matchesInString(string, options: NSMatchingOptions(rawValue: 0), range: NSMakeRange(0, string.characters.count))
            var upRate: Float = 0.00
            var downRate: Float = 0.00
            for result in results {
                downRate += Float((string as NSString).substringWithRange(result.rangeAtIndex(2)))!
                upRate += Float((string as NSString).substringWithRange(result.rangeAtIndex(4)))!
            }
            statusItemView.setRateData(up: upRate, down: downRate)
        }
        catch {}
    }

}