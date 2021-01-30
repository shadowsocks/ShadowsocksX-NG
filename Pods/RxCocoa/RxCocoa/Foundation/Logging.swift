//
//  Logging.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 4/3/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if canImport(FoundationNetworking)
import struct FoundationNetworking.URLRequest
#else
import struct Foundation.URLRequest
#endif

/// Simple logging settings for RxCocoa library.
public struct Logging {
    public typealias LogURLRequest = (URLRequest) -> Bool
    
    /// Log URL requests to standard output in curl format.
    public static var URLRequests: LogURLRequest =  { _ in
    #if DEBUG
        return true
    #else
        return false
    #endif
    }
}
