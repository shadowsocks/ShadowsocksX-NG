//
//  Filter.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 2/17/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {

    /**
     Filters the elements of an observable sequence based on a predicate.

     - seealso: [filter operator on reactivex.io](http://reactivex.io/documentation/operators/filter.html)

     - parameter predicate: A function to test each source element for a condition.
     - returns: An observable sequence that contains elements from the input sequence that satisfy the condition.
     */
    public func filter(_ predicate: @escaping (Element) throws -> Bool)
        -> Observable<Element> {
        Filter(source: self.asObservable(), predicate: predicate)
    }
}

extension ObservableType {
    /**
     Skips elements and completes (or errors) when the observable sequence completes (or errors). Equivalent to filter that always returns false.

     - seealso: [ignoreElements operator on reactivex.io](http://reactivex.io/documentation/operators/ignoreelements.html)

     - returns: An observable sequence that skips all elements of the source sequence.
     */
    public func ignoreElements()
        -> Observable<Never> {
        self.flatMap { _ in Observable<Never>.empty() }
    }
}

final private class FilterSink<Observer: ObserverType>: Sink<Observer>, ObserverType {
    typealias Predicate = (Element) throws -> Bool
    typealias Element = Observer.Element
    
    private let predicate: Predicate
    
    init(predicate: @escaping Predicate, observer: Observer, cancel: Cancelable) {
        self.predicate = predicate
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<Element>) {
        switch event {
        case .next(let value):
            do {
                let satisfies = try self.predicate(value)
                if satisfies {
                    self.forwardOn(.next(value))
                }
            }
            catch let e {
                self.forwardOn(.error(e))
                self.dispose()
            }
        case .completed, .error:
            self.forwardOn(event)
            self.dispose()
        }
    }
}

final private class Filter<Element>: Producer<Element> {
    typealias Predicate = (Element) throws -> Bool
    
    private let source: Observable<Element>
    private let predicate: Predicate
    
    init(source: Observable<Element>, predicate: @escaping Predicate) {
        self.source = source
        self.predicate = predicate
    }
    
    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == Element {
        let sink = FilterSink(predicate: self.predicate, observer: observer, cancel: cancel)
        let subscription = self.source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
