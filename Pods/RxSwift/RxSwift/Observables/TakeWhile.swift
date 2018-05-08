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
        return TakeWhile(source: asObservable(), predicate: predicate)
    }
}

final fileprivate class TakeWhileSink<O: ObserverType>
    : Sink<O>
    , ObserverType {
    typealias Element = O.E
    typealias Parent = TakeWhile<Element>

    fileprivate let _parent: Parent

    fileprivate var _running = true

    init(parent: Parent, observer: O, cancel: Cancelable) {
        _parent = parent
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<Element>) {
        switch event {
        case .next(let value):
            if !_running {
                return
            }
            
            do {
                _running = try _parent._predicate(value)
            } catch let e {
                forwardOn(.error(e))
                dispose()
                return
            }
            
            if _running {
                forwardOn(.next(value))
            } else {
                forwardOn(.completed)
                dispose()
            }
        case .error, .completed:
            forwardOn(event)
            dispose()
        }
    }
    
}

final fileprivate class TakeWhile<Element>: Producer<Element> {
    typealias Predicate = (Element) throws -> Bool

    fileprivate let _source: Observable<Element>
    fileprivate let _predicate: Predicate

    init(source: Observable<Element>, predicate: @escaping Predicate) {
        _source = source
        _predicate = predicate
    }

    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        let sink = TakeWhileSink(parent: self, observer: observer, cancel: cancel)
        let subscription = _source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
