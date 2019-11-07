//
//  TakeWhile.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 6/7/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {

    /**
     Returns elements from an observable sequence as long as a specified condition is true.

     - seealso: [takeWhile operator on reactivex.io](http://reactivex.io/documentation/operators/takewhile.html)

     - parameter predicate: A function to test each element for a condition.
     - returns: An observable sequence that contains the elements from the input sequence that occur before the element at which the test no longer passes.
     */
    public func takeWhile(_ predicate: @escaping (E) throws -> Bool)
        -> Observable<E> {
        return TakeWhile(source: self.asObservable(), predicate: predicate)
    }
}

final private class TakeWhileSink<O: ObserverType>
    : Sink<O>
    , ObserverType {
    typealias Element = O.E
    typealias Parent = TakeWhile<Element>

    fileprivate let _parent: Parent

    fileprivate var _running = true

    init(parent: Parent, observer: O, cancel: Cancelable) {
        self._parent = parent
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<Element>) {
        switch event {
        case .next(let value):
            if !self._running {
                return
            }
            
            do {
                self._running = try self._parent._predicate(value)
            } catch let e {
                self.forwardOn(.error(e))
                self.dispose()
                return
            }
            
            if self._running {
                self.forwardOn(.next(value))
            } else {
                self.forwardOn(.completed)
                self.dispose()
            }
        case .error, .completed:
            self.forwardOn(event)
            self.dispose()
        }
    }
    
}

final private class TakeWhile<Element>: Producer<Element> {
    typealias Predicate = (Element) throws -> Bool

    fileprivate let _source: Observable<Element>
    fileprivate let _predicate: Predicate

    init(source: Observable<Element>, predicate: @escaping Predicate) {
        self._source = source
        self._predicate = predicate
    }

    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        let sink = TakeWhileSink(parent: self, observer: observer, cancel: cancel)
        let subscription = self._source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
