//
//  DeprecationWarner.swift
//  Platform
//
//  Created by Shai Mishali on 1/9/18.
//  Copyright © 2018 Krunoslav Zaher. All rights reserved.
//

import Foundation

#if DEBUG
    class DeprecationWarner {
        private static var warned = Set<Kind>()
        private static var _lock = NSRecursiveLock()
        
        static func warnIfNeeded(_ kind: Kind) {
            _lock.lock(); defer { _lock.unlock() }
            guard !warned.contains(kind) else { return }
            
            warned.insert(kind)
            print("ℹ️ [DEPRECATED] \(kind.message)")
        }
    }
    
    extension DeprecationWarner {
        enum Kind {
            case variable
            case globalTestFunctionNext
            case globalTestFunctionError
            case globalTestFunctionCompleted
            
            var message: String {
                switch self {
                case .variable: return "`Variable` is planned for future deprecation. Please consider `BehaviorRelay` as a replacement. Read more at: https://git.io/vNqvx"
                case .globalTestFunctionNext: return "The `next()` global function is planned for future deprecation. Please use `Recorded.next()` instead."
                case .globalTestFunctionError: return "The `error()` global function is planned for future deprecation. Please use `Recorded.error()` instead."
                case .globalTestFunctionCompleted: return "The `completed()` global function is planned for future deprecation. Please use `Recorded.completed()` instead."
                }
            }
        }
    }
#endif

