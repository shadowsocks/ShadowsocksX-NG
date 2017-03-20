//
//  Bag+Rx.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 10/19/16.
//  Copyright © 2016 Krunoslav Zaher. All rights reserved.
//


// MARK: forEach

@inline(__always)
func dispatch<E>(_ bag: Bag<(Event<E>) -> ()>, _ event: Event<E>) {
    if bag._onlyFastPath {
        bag._value0?(event)
        return
    }

    let value0 = bag._value0
    let dictionary = bag._dictionary

    if let value0 = value0 {
        value0(event)
    }

    let pairs = bag._pairs
    for i in 0 ..< pairs.count {
        pairs[i].value(event)
    }

    if let dictionary = dictionary {
        for element in dictionary.values {
            element(event)
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

    let pairs = bag._pairs
    for i in 0 ..< pairs.count {
        pairs[i].value.dispose()
    }

    if let dictionary = dictionary {
        for element in dictionary.values {
            element.dispose()
        }
    }
}
