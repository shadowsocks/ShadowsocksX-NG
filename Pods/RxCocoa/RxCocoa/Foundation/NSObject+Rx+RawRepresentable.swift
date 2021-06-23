//
//  NSObject+Rx+RawRepresentable.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 11/9/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if !os(Linux)

import RxSwift

import Foundation

extension Reactive where Base: NSObject {
    /**
     Specialization of generic `observe` method.

     This specialization first observes `KVORepresentable` value and then converts it to `RawRepresentable` value.
     
     It is useful for observing bridged ObjC enum values.

     For more information take a look at `observe` method.
     */
    public func observe<Element: RawRepresentable>(_ type: Element.Type, _ keyPath: String, options: KeyValueObservingOptions = [.new, .initial], retainSelf: Bool = true) -> Observable<Element?> where Element.RawValue: KVORepresentable {
        return self.observe(Element.RawValue.KVOType.self, keyPath, options: options, retainSelf: retainSelf)
            .map(Element.init)
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
        public func observeWeakly<Element: RawRepresentable>(_ type: Element.Type, _ keyPath: String, options: KeyValueObservingOptions = [.new, .initial]) -> Observable<Element?> where Element.RawValue: KVORepresentable {
            return self.observeWeakly(Element.RawValue.KVOType.self, keyPath, options: options)
                .map(Element.init)
        }
    }
#endif

#endif
