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
        if length % 4 == 0 {
            return string
        } else {
            length = 4 - length % 4 + length
            return string.padding(toLength: length, withPad: "=", startingAt: 0)
        }
    }

    if url?.host == nil {
        return nil
    }

    var plainUrl: URLComponents! = URLComponents(url: url!,
                                                 resolvingAgainstBaseURL: false)

    let data = Data(base64Encoded: padBase64(string: url!.host!),
                    options: Data.Base64DecodingOptions())

    if data != nil {
        let decoded = String(data: data!, encoding: String.Encoding.utf8)
        plainUrl = URLComponents(string: "ss://\(decoded!)")

        if plainUrl == nil {
            return nil
        }
    }

    let remark = plainUrl.queryItems?
        .filter({ $0.name == "Remark" }).first?.value
    let otaStr = plainUrl.queryItems?
        .filter({ $0.name == "OTA" }).first?.value

    var ota: Bool? = nil
    if otaStr != nil {
        ota = NSString(string: otaStr!).boolValue
    }

    return ["ServerHost": plainUrl.host,
            "ServerPort": UInt16(plainUrl.port!),
            "Method": plainUrl.user,
            "Password": plainUrl.password,
            "Remark": remark,
            "OTA": ota,
    ]
}
