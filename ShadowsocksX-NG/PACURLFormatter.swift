//
//  PACURLFormatter.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 2019/9/15.
//  Copyright © 2019 qiuyuzhou. All rights reserved.
//

import Cocoa



class PACURLFormatter: Formatter {
    override func string(for obj: Any?) -> String? {
        if let _obj = obj {
            switch _obj {
            case let s as String:
                return s
            default:
                return ""
            }
        }
        return ""
    }
    
    override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {

        let input = string.trimmingCharacters(in: .whitespaces)
        if input == "" {
            return true
        }

        let errorMessage = "Must be a valid URL with scheme 'file', 'http' or 'https'".localized
        
        if let url = URL.init(string: input) {
            if let scheme = url.scheme {
                if !(["http", "https", "file"].contains(scheme) ) {
                    error?.pointee = errorMessage as NSString
                    return false
                }
                
                obj?.pointee = url.absoluteString as AnyObject
                return true
            } else {
                error?.pointee = errorMessage as NSString
                return false
            }
        } else {
            error?.pointee = errorMessage as NSString
            return false
        }
    }
}
