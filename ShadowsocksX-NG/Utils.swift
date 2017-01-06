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

func ParseSSURL(_ url: URL?) -> [String: Any?]? {

    func padBase64(string: String) -> String {
        var length = string.characters.count
        length = 4 - length % 4 + length
        return string.padding(toLength: length, withPad: "=", startingAt: 0)
    }

    if url?.host == nil {
        return nil
    }

    var plainUrl: URL! = url

    let data = Data(base64Encoded: padBase64(string: url!.host!),
                    options: Data.Base64DecodingOptions())

    if data != nil {
        let decoded = String(data: data!, encoding: String.Encoding.utf8)
        plainUrl = URL(string: "ss://\(decoded!)")

        if plainUrl == nil {
            return nil
        }
    }

    return ["ServerHost": plainUrl.host,
            "ServerPort": UInt16(plainUrl.port!),
            "Method": plainUrl.user,
            "Password": plainUrl.password,
    ]
}
