//
//  NSObject+Rx+KVORepresentable.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 11/14/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if !os(Linux)

import Foundation.NSObject
#if !RX_NO_MODULE
    import RxSwift
#endif

extension Reactive where Base: NSObject {

    /**
     Specialization of generic `observe` method.

     This is a special overload because to observe values of some type (for example `Int`), first values of KVO type
     need to be observed (`NSNumber`), and then converted to result type.

     For more information take a look at `observe` method.
     */
    public func observe<E: KVORepresentable>(_ type: E.Type, _ keyPath: String, options: NSKeyValueObservingOptions = [.new, .initial], retainSelf: Bool = true) -> Observable<E?> {
        return observe(E.KVOType.self, keyPath, options: options, retainSelf: retainSelf)
            .map(E.init)
    }
}

#if !DISABLE_SWIZZLING && !os(Linux)
    // KVO
    extension Reactive where Base: NSObject {
        /**
        Specialization of generic `observeWeakly` method.

        For more information take a look at `observeWeakly` method.
        */
        public func observeWeakly<E: KVORepresentable>(_ type: E.Type, _ keyPath: String, options: NSKeyValueObservingOptions = [.new, .initial]) -> Observable<E?> {
            return observeWeakly(E.KVOType.self, keyPath, options: options)
                .map(E.init)
        }
    }
#endif

#endif
