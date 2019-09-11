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
        return NSLocalizedString(self, tableName: "Localizable", comment: "")
    }
    
    func localized(withComment:String) -> String {
        return NSLocalizedString(self, tableName: "Localizable", comment: withComment)
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

enum ProxyType {
    case pac
    case global
}

struct Globals {
    static var proxyType = ProxyType.pac
}
