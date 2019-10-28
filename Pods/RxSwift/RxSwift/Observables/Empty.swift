//
//  Empty.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 8/30/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {
    /**
     Returns an empty observable sequence, using the specified scheduler to send out the single `Completed` message.

     - seealso: [empty operator on reactivex.io](http://reactivex.io/documentation/operators/empty-never-throw.html)

     - returns: An observable sequence with no elements.
     */
    public static func empty() -> Observable<E> {
        return EmptyProducer<E>()
    }
}

final private class EmptyProducer<Element>: Producer<Element> {
    override func subscribe<O: ObserverType>(_ observer: O) -> Disposable where O.E == Element {
        observer.on(.completed)
        return Disposables.create()
    }
}
