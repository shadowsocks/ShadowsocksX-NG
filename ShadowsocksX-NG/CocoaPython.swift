//
//  CocoaPython.swift
//  ShadowsocksX-NG
//
//  Created by XJY on 2020/4/4.
//  Copyright © 2020 qiuyuzhou. All rights reserved.
//

import Cocoa

public typealias completeBlock = ((_ results: [String], _ errors: String?)->Void)

public class CocoaPython {

    let buildTask = Process()
    let outPip = Pipe()
    let errorPipe = Pipe()
    /// 完成回调
    var completed: completeBlock?
    
    /// 是否异步执行回调，只在runAsync下生效
    var asyncComlete = false
    
    /// 多个返回结果的分隔符
    public var splitPara: Character?

    public init(scrPath: String, args: [String]? = nil, complete: completeBlock? = nil) {
        completed = complete
        
        buildTask.launchPath = "/usr/local/bin/python3"

        var allArgs = [String]()
        allArgs.append(scrPath)
        if let aArg = args {
            allArgs.append(contentsOf: aArg)
        }
        buildTask.arguments = allArgs

        buildTask.standardInput = Pipe()
        buildTask.standardOutput = outPip
        buildTask.standardError = errorPipe
        
//        buildTask.terminationHandler = { p in
//            self.taskFinish()
//        }
    }
    
    /// 同步执行
    public func runSync() {
        buildTask.launch()
        buildTask.waitUntilExit()
        
//        // 错误处理
//        if let aError = fetchResult(errorPipe), aError != "" {
//            runComlete(["-1"], aError)
//            return
//        }
        
//        let result = fetchResult(outPip)?.split(separator: "\n").map(String.init) ?? [""]
        runComlete(processResult(), fetchResult(errorPipe))
    }
    
    /// 异步执行
    ///
    /// - Parameter asyncComlete: 回调是否异步主线程执行
    public func runAsync(asyncComlete: Bool = true) {
        self.asyncComlete = asyncComlete
        DispatchQueue.global().async {
            self.runSync()
        }
    }
}

extension CocoaPython {
    
    /// 执行block回调
    fileprivate func runComlete(_ result: [String], _ error: String?) {
        if asyncComlete {
            asyncComlete = false
            DispatchQueue.main.async {
                self.completed?(result, error)
            }
        } else {
            completed?(result, error)
        }
    }
    
    // 获取返回数据的字符串形式
    fileprivate func fetchResult(_ pipe: Pipe) -> String? {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: String.Encoding.utf8)
    }
    
    fileprivate func processResult() -> [String] {
        let result = fetchResult(outPip) ?? ""
        guard let splt = splitPara else { return [result] }
        return result.split(separator: splt).map(String.init)
    }
}

