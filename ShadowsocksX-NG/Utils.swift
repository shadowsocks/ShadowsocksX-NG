//
//  Utils.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/7.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Foundation

extension String {
    var localized: String {
        return NSLocalizedString(self, tableName: nil, bundle: Bundle.main, value: "", comment: "")
    }
    
    func jsonDictionaryArray() -> [[String: Any]]? {
        if let data = data(using: .utf8) {
            do {
                return try JSONSerialization.jsonObject(with: data, options: []) as? [[String:Any]]
            } catch let error as NSError {
                print(error)
            }
        }
        
        return nil
    }
}

extension Data {
    func sha1() -> String {
        let data = self
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        CC_SHA1((data as NSData).bytes, CC_LONG(data.count), &digest)
        let hexBytes = digest.map { String(format: "%02hhx", $0) }
        return hexBytes.joined(separator: "")
    }
}

extension Collection where Iterator.Element == [String: Any] {
    func toJSONString(options: JSONSerialization.WritingOptions = .prettyPrinted) -> String {
        if let array = self as? [[String: Any]],
            let data = try? JSONSerialization.data(withJSONObject: array, options: options),
            let string = String(data: data, encoding: String.Encoding.utf8) {
            
            return string
        }
        
        return "[]"
    }
}

enum ProxyType {
    case pac
    case global
}

struct Globals {
    static var proxyType = ProxyType.pac
}
