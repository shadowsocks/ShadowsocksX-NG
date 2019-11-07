//
//  SkipWhile.swift
//  RxSwift
//
//  Created by Yury Korolev on 10/9/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {

    /**
     Bypasses elements in an observable sequence as long as a specified condition is true and then returns the remaining elements.

     - seealso: [skipWhile operator on reactivex.io](http://reactivex.io/documentation/operators/skipwhile.html)

     - parameter predicate: A function to test each element for a condition.
     - returns: An observable sequence that contains the elements from the input sequence starting at the first element in the linear series that does not pass the test specified by predicate.
     */
    public func skipWhile(_ predicate: @escaping (E) throws -> Bool) -> Observable<E> {
        return SkipWhile(source: self.asObservable(), predicate: predicate)
    }
}

final private class SkipWhileSink<O: ObserverType>: Sink<O>, ObserverType {
    typealias Element = O.E
    typealias Parent = SkipWhile<Element>

    fileprivate let _parent: Parent
    fileprivate var _running = false

    init(parent: Parent, observer: O, cancel: Cancelable) {
        self._parent = parent
        super.init(observer: observer, cancel: cancel)
    }

    func on(_ event: Event<Element>) {
        switch event {
        case .next(let value):
            if !self._running {
                do {
                    self._running = try !self._parent._predicate(value)
                } catch let e {
                    self.forwardOn(.error(e))
                    self.dispose()
                    return
                }
            }

            if self._running {
                self.forwardOn(.next(value))
            }
        case .error, .completed:
            self.forwardOn(event)
            self.dispose()
        }
    }
}

final private class SkipWhile<Element>: Producer<Element> {
    typealias Predicate = (Element) throws -> Bool

    fileprivate let _source: Observable<Element>
    fileprivate let _predicate: Predicate

    init(source: Observable<Element>, predicate: @escaping Predicate) {
        self._source = source
        self._predicate = predicate
    }

    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        let sink = SkipWhileSink(parent: self, observer: observer, cancel: cancel)
        let subscription = self._source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
