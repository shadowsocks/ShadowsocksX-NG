//
//  StartWith.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 4/6/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {

    /**
     Prepends a sequence of values to an observable sequence.

     - seealso: [startWith operator on reactivex.io](http://reactivex.io/documentation/operators/startwith.html)

     - parameter elements: Elements to prepend to the specified sequence.
     - returns: The source sequence prepended with the specified values.
     */
    public func startWith(_ elements: Element ...)
        -> Observable<Element> {
            return StartWith(source: self.asObservable(), elements: elements)
    }
}

final private class StartWith<Element>: Producer<Element> {
    let elements: [Element]
    let source: Observable<Element>

    init(source: Observable<Element>, elements: [Element]) {
        self.source = source
        self.elements = elements
        super.init()
    }

    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == Element {
        for e in self.elements {
            observer.on(.next(e))
        }

        return (sink: Disposables.create(), subscription: self.source.subscribe(observer))
    }
}
