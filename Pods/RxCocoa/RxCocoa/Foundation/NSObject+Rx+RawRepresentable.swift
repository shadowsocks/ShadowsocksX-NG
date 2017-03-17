//
//  NSObject+Rx+RawRepresentable.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 11/9/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if !os(Linux)

import Foundation
#if !RX_NO_MODULE
    import RxSwift
#endif

extension Reactive where Base: NSObject {
    /**
     Specialization of generic `observe` method.

     This specialization first observes `KVORepresentable` value and then converts it to `RawRepresentable` value.
     
     It is useful for observing bridged ObjC enum values.

     For more information take a look at `observe` method.
     */
    public func observe<E: RawRepresentable>(_ type: E.Type, _ keyPath: String, options: NSKeyValueObservingOptions = [.new, .initial], retainSelf: Bool = true) -> Observable<E?> where E.RawValue: KVORepresentable {
        return observe(E.RawValue.KVOType.self, keyPath, options: options, retainSelf: retainSelf)
            .map(E.init)
    }
}

#if !DISABLE_SWIZZLING

    // observeWeakly + RawRepresentable
    extension Reactive where Base: NSObject {

        /**
         Specialization of generic `observeWeakly` method.

         This specialization first observes `KVORepresentable` value and then converts it to `RawRepresentable` value.
     
         It is useful for observing bridged ObjC enum values.

         For more information take a look at `observeWeakly` method.
         */
        public func observeWeakly<E: RawRepresentable>(_ type: E.Type, _ keyPath: String, options: NSKeyValueObservingOptions = [.new, .initial]) -> Observable<E?> where E.RawValue: KVORepresentable {
            return observeWeakly(E.RawValue.KVOType.self, keyPath, options: options)
                .map(E.init)
        }
    }
#endif

#endif
