//
//  Bag+Rx.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 10/19/16.
//  Copyright © 2016 Krunoslav Zaher. All rights reserved.
//


// MARK: forEach

@inline(__always)
func dispatch<Element>(_ bag: Bag<(Event<Element>) -> Void>, _ event: Event<Element>) {
    bag._value0?(event)

    if bag._onlyFastPath {
        return
    }

    let pairs = bag._pairs
    for i in 0 ..< pairs.count {
        pairs[i].value(event)
    }

    if let dictionary = bag._dictionary {
        for element in dictionary.values {
            element(event)
        }
    }
}

/// Dispatches `dispose` to all disposables contained inside bag.
func disposeAll(in bag: Bag<Disposable>) {
    bag._value0?.dispose()

    if bag._onlyFastPath {
        return
    }

    let pairs = bag._pairs
    for i in 0 ..< pairs.count {
        pairs[i].value.dispose()
    }

    if let dictionary = bag._dictionary {
        for element in dictionary.values {
            element.dispose()
        }
    }
}
