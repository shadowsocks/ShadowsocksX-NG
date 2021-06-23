//
//  NSObject+Rx+KVORepresentable.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 11/14/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if !os(Linux)

import Foundation
import RxSwift

/// Key value observing options
public struct KeyValueObservingOptions: OptionSet {
    /// Raw value
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    /// Whether a sequence element should be sent to the observer immediately, before the subscribe method even returns.
    public static let initial = KeyValueObservingOptions(rawValue: 1 << 0)
    /// Whether to send updated values.
    public static let new = KeyValueObservingOptions(rawValue: 1 << 1)
}

extension Reactive where Base: NSObject {

    /**
     Specialization of generic `observe` method.

     This is a special overload because to observe values of some type (for example `Int`), first values of KVO type
     need to be observed (`NSNumber`), and then converted to result type.

     For more information take a look at `observe` method.
     */
    public func observe<Element: KVORepresentable>(_ type: Element.Type, _ keyPath: String, options: KeyValueObservingOptions = [.new, .initial], retainSelf: Bool = true) -> Observable<Element?> {
        return self.observe(Element.KVOType.self, keyPath, options: options, retainSelf: retainSelf)
            .map(Element.init)
    }
}

#if !DISABLE_SWIZZLING && !os(Linux)
    // KVO
    extension Reactive where Base: NSObject {
        /**
        Specialization of generic `observeWeakly` method.

        For more information take a look at `observeWeakly` method.
        */
        public func observeWeakly<Element: KVORepresentable>(_ type: Element.Type, _ keyPath: String, options: KeyValueObservingOptions = [.new, .initial]) -> Observable<Element?> {
            return self.observeWeakly(Element.KVOType.self, keyPath, options: options)
                .map(Element.init)
        }
    }
#endif

#endif
