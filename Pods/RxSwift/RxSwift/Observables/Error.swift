//
//  Error.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 8/30/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {
    /**
     Returns an observable sequence that terminates with an `error`.

     - seealso: [throw operator on reactivex.io](http://reactivex.io/documentation/operators/empty-never-throw.html)

     - returns: The observable sequence that terminates with specified error.
     */
    public static func error(_ error: Swift.Error) -> Observable<Element> {
        ErrorProducer(error: error)
    }
}

final private class ErrorProducer<Element>: Producer<Element> {
    private let error: Swift.Error
    
    init(error: Swift.Error) {
        self.error = error
    }
    
    override func subscribe<Observer: ObserverType>(_ observer: Observer) -> Disposable where Observer.Element == Element {
        observer.on(.error(self.error))
        return Disposables.create()
    }
}
