//
//  RxMutableBox.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 5/22/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if os(Linux)
/// As Swift 5 was released, A patch to `Thread` for Linux
/// changed `threadDictionary` to a `NSMutableDictionary` instead of
/// a `Dictionary<String, Any>`: https://github.com/apple/swift-corelibs-foundation/pull/1762/files
///
/// This means that on Linux specifically, `RxMutableBox` must be a `NSObject`
/// or it won't be possible to store it in `Thread.threadDictionary`.
///
/// For more information, read the discussion at:
/// https://github.com/ReactiveX/RxSwift/issues/1911#issuecomment-479723298
import class Foundation.NSObject

/// Creates mutable reference wrapper for any type.
final class RxMutableBox<T>: NSObject {
    /// Wrapped value
    var value: T

    /// Creates reference wrapper for `value`.
    ///
    /// - parameter value: Value to wrap.
    init (_ value: T) {
        self.value = value
    }
}
#else
/// Creates mutable reference wrapper for any type.
final class RxMutableBox<T>: CustomDebugStringConvertible {
    /// Wrapped value
    var value: T
    
    /// Creates reference wrapper for `value`.
    ///
    /// - parameter value: Value to wrap.
    init (_ value: T) {
        self.value = value
    }
}

extension RxMutableBox {
    /// - returns: Box description.
    var debugDescription: String {
        return "MutatingBox(\(self.value))"
    }
}
#endif
