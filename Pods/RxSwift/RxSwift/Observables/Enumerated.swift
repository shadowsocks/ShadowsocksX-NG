//
//  Enumerated.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 8/6/17.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {

    /**
     Enumerates the elements of an observable sequence.

     - seealso: [map operator on reactivex.io](http://reactivex.io/documentation/operators/map.html)

     - returns: An observable sequence that contains tuples of source sequence elements and their indexes.
     */
    public func enumerated()
        -> Observable<(index: Int, element: Element)> {
        Enumerated(source: self.asObservable())
    }
}

final private class EnumeratedSink<Element, Observer: ObserverType>: Sink<Observer>, ObserverType where Observer.Element == (index: Int, element: Element) {
    var index = 0
    
    func on(_ event: Event<Element>) {
        switch event {
        case .next(let value):
            do {
                let nextIndex = try incrementChecked(&self.index)
                let next = (index: nextIndex, element: value)
                self.forwardOn(.next(next))
            }
            catch let e {
                self.forwardOn(.error(e))
                self.dispose()
            }
        case .completed:
            self.forwardOn(.completed)
            self.dispose()
        case .error(let error):
            self.forwardOn(.error(error))
            self.dispose()
        }
    }
}

final private class Enumerated<Element>: Producer<(index: Int, element: Element)> {
    private let source: Observable<Element>

    init(source: Observable<Element>) {
        self.source = source
    }

    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == (index: Int, element: Element) {
        let sink = EnumeratedSink<Element, Observer>(observer: observer, cancel: cancel)
        let subscription = self.source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
