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
    public func filter(_ predicate: @escaping (E) throws -> Bool)
        -> Observable<E> {
        return Filter(source: asObservable(), predicate: predicate)
    }
}

extension ObservableType {

    /**
     Skips elements and completes (or errors) when the receiver completes (or errors). Equivalent to filter that always returns false.

     - seealso: [ignoreElements operator on reactivex.io](http://reactivex.io/documentation/operators/ignoreelements.html)

     - returns: An observable sequence that skips all elements of the source sequence.
     */
    public func ignoreElements()
        -> Completable {
            return flatMap { _ in
                return Observable<Never>.empty()
            }
            .asCompletable()
    }
}

final fileprivate class FilterSink<O : ObserverType>: Sink<O>, ObserverType {
    typealias Predicate = (Element) throws -> Bool
    typealias Element = O.E
    
    private let _predicate: Predicate
    
    init(predicate: @escaping Predicate, observer: O, cancel: Cancelable) {
        _predicate = predicate
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<Element>) {
        switch event {
            case .next(let value):
                do {
                    let satisfies = try _predicate(value)
                    if satisfies {
                        forwardOn(.next(value))
                    }
                }
                catch let e {
                    forwardOn(.error(e))
                    dispose()
                }
            case .completed, .error:
                forwardOn(event)
                dispose()
        }
    }
}

final fileprivate class Filter<Element> : Producer<Element> {
    typealias Predicate = (Element) throws -> Bool
    
    private let _source: Observable<Element>
    private let _predicate: Predicate
    
    init(source: Observable<Element>, predicate: @escaping Predicate) {
        _source = source
        _predicate = predicate
    }
    
    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        let sink = FilterSink(predicate: _predicate, observer: observer, cancel: cancel)
        let subscription = _source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
