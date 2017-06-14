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

func splitProfile(url: String, max: Int) -> [String] {
    let ssrregexp = "ssr://([A-Za-z0-9_-]+)"
    let ssregexp = "ss://([A-Za-z0-9_-]+"

    
    if url.hasPrefix("ss://"){
        return splitor(url: url, regexp: ssregexp)
    }else if url.hasPrefix("ssr://"){
        return splitor(url: url, regexp: ssrregexp)
    }
    return [""]
}

fileprivate func splitor(url: String, regexp: String) -> [String] {
    var ret: [String] = []
    var ssrUrl = url
    while ssrUrl.range(of:regexp, options: .regularExpression) != nil{
        let range = ssrUrl.range(of:regexp, options: .regularExpression)
        let result = ssrUrl.substring(with:range!)
        ssrUrl.replaceSubrange(range!, with: "")
        ret.append(result)
    }
    return ret
}
