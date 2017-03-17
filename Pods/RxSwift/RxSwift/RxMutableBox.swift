//
//  RxMutableBox.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 5/22/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

/// Creates mutable reference wrapper for any type.
class RxMutableBox<T> : CustomDebugStringConvertible {
    /// Wrapped value
    var value : T
    
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
