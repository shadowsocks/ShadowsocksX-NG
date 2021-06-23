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
    public func skip(while predicate: @escaping (Element) throws -> Bool) -> Observable<Element> {
        SkipWhile(source: self.asObservable(), predicate: predicate)
    }

    /**
     Bypasses elements in an observable sequence as long as a specified condition is true and then returns the remaining elements.

     - seealso: [skipWhile operator on reactivex.io](http://reactivex.io/documentation/operators/skipwhile.html)

     - parameter predicate: A function to test each element for a condition.
     - returns: An observable sequence that contains the elements from the input sequence starting at the first element in the linear series that does not pass the test specified by predicate.
     */
    @available(*, deprecated, renamed: "skip(while:)")
    public func skipWhile(_ predicate: @escaping (Element) throws -> Bool) -> Observable<Element> {
        SkipWhile(source: self.asObservable(), predicate: predicate)
    }
}

final private class SkipWhileSink<Observer: ObserverType>: Sink<Observer>, ObserverType {
    typealias Element = Observer.Element 
    typealias Parent = SkipWhile<Element>

    private let parent: Parent
    private var running = false

    init(parent: Parent, observer: Observer, cancel: Cancelable) {
        self.parent = parent
        super.init(observer: observer, cancel: cancel)
    }

    func on(_ event: Event<Element>) {
        switch event {
        case .next(let value):
            if !self.running {
                do {
                    self.running = try !self.parent.predicate(value)
                } catch let e {
                    self.forwardOn(.error(e))
                    self.dispose()
                    return
                }
            }

            if self.running {
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

    private let source: Observable<Element>
    fileprivate let predicate: Predicate

    init(source: Observable<Element>, predicate: @escaping Predicate) {
        self.source = source
        self.predicate = predicate
    }

    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == Element {
        let sink = SkipWhileSink(parent: self, observer: observer, cancel: cancel)
        let subscription = self.source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
