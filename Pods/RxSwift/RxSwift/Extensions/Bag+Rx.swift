//
//  Bag+Rx.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 10/19/16.
//  Copyright © 2016 Krunoslav Zaher. All rights reserved.
//

import Foundation


// MARK: forEach

extension Bag where T: ObserverType {
    /// Dispatches `event` to app observers contained inside bag.
    ///
    /// - parameter action: Enumeration closure.
    func on(_ event: Event<T.E>) {
        if _onlyFastPath {
            _value0?.on(event)
            return
        }

        let value0 = _value0
        let dictionary = _dictionary

        if let value0 = value0 {
            value0.on(event)
        }

        if let dictionary = dictionary {
            for element in dictionary.values {
                element.on(event)
            }
        }
    }
}

/// Dispatches `dispose` to all disposables contained inside bag.
func disposeAll(in bag: Bag<Disposable>) {
    if bag._onlyFastPath {
        bag._value0?.dispose()
        return
    }

    let value0 = bag._value0
    let dictionary = bag._dictionary

    if let value0 = value0 {
        value0.dispose()
    }

    if let dictionary = dictionary {
        for element in dictionary.values {
            element.dispose()
        }
    }
}
