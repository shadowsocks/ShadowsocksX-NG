//
//  Observable+Single.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 2/14/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

// MARK: distinct until changed

extension ObservableType where E: Equatable {
    
    /**
    Returns an observable sequence that contains only distinct contiguous elements according to equality operator.

    - seealso: [distinct operator on reactivex.io](http://reactivex.io/documentation/operators/distinct.html)
    
    - returns: An observable sequence only containing the distinct contiguous elements, based on equality operator, from the source sequence.
    */
    public func distinctUntilChanged()
        -> Observable<E> {
        return self.distinctUntilChanged({ $0 }, comparer: { ($0 == $1) })
    }
}

extension ObservableType {
    /**
    Returns an observable sequence that contains only distinct contiguous elements according to the `keySelector`.

    - seealso: [distinct operator on reactivex.io](http://reactivex.io/documentation/operators/distinct.html)
    
    - parameter keySelector: A function to compute the comparison key for each element.
    - returns: An observable sequence only containing the distinct contiguous elements, based on a computed key value, from the source sequence.
    */
    public func distinctUntilChanged<K: Equatable>(_ keySelector: @escaping (E) throws -> K)
        -> Observable<E> {
        return self.distinctUntilChanged(keySelector, comparer: { $0 == $1 })
    }

    /**
    Returns an observable sequence that contains only distinct contiguous elements according to the `comparer`.

    - seealso: [distinct operator on reactivex.io](http://reactivex.io/documentation/operators/distinct.html)
    
    - parameter comparer: Equality comparer for computed key values.
    - returns: An observable sequence only containing the distinct contiguous elements, based on `comparer`, from the source sequence.
    */
    public func distinctUntilChanged(_ comparer: @escaping (E, E) throws -> Bool)
        -> Observable<E> {
        return self.distinctUntilChanged({ $0 }, comparer: comparer)
    }
    
    /**
    Returns an observable sequence that contains only distinct contiguous elements according to the keySelector and the comparer.

    - seealso: [distinct operator on reactivex.io](http://reactivex.io/documentation/operators/distinct.html)
    
    - parameter keySelector: A function to compute the comparison key for each element.
    - parameter comparer: Equality comparer for computed key values.
    - returns: An observable sequence only containing the distinct contiguous elements, based on a computed key value and the comparer, from the source sequence.
    */
    public func distinctUntilChanged<K>(_ keySelector: @escaping (E) throws -> K, comparer: @escaping (K, K) throws -> Bool)
        -> Observable<E> {
        return DistinctUntilChanged(source: self.asObservable(), selector: keySelector, comparer: comparer)
    }
}

// MARK: doOn

extension ObservableType {
    /**
     Invokes an action for each event in the observable sequence, and propagates all observer messages through the result sequence.

     - seealso: [do operator on reactivex.io](http://reactivex.io/documentation/operators/do.html)

     - parameter onNext: Action to invoke for each element in the observable sequence.
     - parameter onError: Action to invoke upon errored termination of the observable sequence.
     - parameter onCompleted: Action to invoke upon graceful termination of the observable sequence.
     - parameter onSubscribe: Action to invoke before subscribing to source observable sequence.
     - parameter onDispose: Action to invoke after subscription to source observable has been disposed for any reason. It can be either because sequence terminates for some reason or observer subscription being disposed.
    - returns: The source sequence with the side-effecting behavior applied.
     */
    public func `do`(onNext: ((E) throws -> Void)? = nil, onError: ((Swift.Error) throws -> Void)? = nil, onCompleted: (() throws -> Void)? = nil, onSubscribe: (() -> ())? = nil, onDispose: (() -> ())? = nil)
        -> Observable<E> {
            return Do(source: self.asObservable(), eventHandler: { e in
                switch e {
                case .next(let element):
                    try onNext?(element)
                case .error(let e):
                    try onError?(e)
                case .completed:
                    try onCompleted?()
                }
            }, onSubscribe: onSubscribe, onDispose: onDispose)
    }
}

// MARK: startWith

extension ObservableType {
    
    /**
    Prepends a sequence of values to an observable sequence.

    - seealso: [startWith operator on reactivex.io](http://reactivex.io/documentation/operators/startwith.html)
    
    - parameter elements: Elements to prepend to the specified sequence.
    - returns: The source sequence prepended with the specified values.
    */
    public func startWith(_ elements: E ...)
        -> Observable<E> {
        return StartWith(source: self.asObservable(), elements: elements)
    }
}

// MARK: retry

extension ObservableType {
    
    /**
    Repeats the source observable sequence until it successfully terminates.
    
    **This could potentially create an infinite sequence.**

    - seealso: [retry operator on reactivex.io](http://reactivex.io/documentation/operators/retry.html)
    
    - returns: Observable sequence to repeat until it successfully terminates.
    */
    public func retry() -> Observable<E> {
        return CatchSequence(sources: InfiniteSequence(repeatedValue: self.asObservable()))
    }

    /**
    Repeats the source observable sequence the specified number of times in case of an error or until it successfully terminates.
    
    If you encounter an error and want it to retry once, then you must use `retry(2)`

    - seealso: [retry operator on reactivex.io](http://reactivex.io/documentation/operators/retry.html)

    - parameter maxAttemptCount: Maximum number of times to repeat the sequence.
    - returns: An observable sequence producing the elements of the given sequence repeatedly until it terminates successfully.
    */
    public func retry(_ maxAttemptCount: Int)
        -> Observable<E> {
        return CatchSequence(sources: repeatElement(self.asObservable(), count: maxAttemptCount))
    }
    
    /**
    Repeats the source observable sequence on error when the notifier emits a next value.
    If the source observable errors and the notifier completes, it will complete the source sequence.

    - seealso: [retry operator on reactivex.io](http://reactivex.io/documentation/operators/retry.html)
    
    - parameter notificationHandler: A handler that is passed an observable sequence of errors raised by the source observable and returns and observable that either continues, completes or errors. This behavior is then applied to the source observable.
    - returns: An observable sequence producing the elements of the given sequence repeatedly until it terminates successfully or is notified to error or complete.
    */
    public func retryWhen<TriggerObservable: ObservableType, Error: Swift.Error>(_ notificationHandler: @escaping (Observable<Error>) -> TriggerObservable)
        -> Observable<E> {
            return RetryWhenSequence(sources: InfiniteSequence(repeatedValue: self.asObservable()), notificationHandler: notificationHandler)
    }

    /**
    Repeats the source observable sequence on error when the notifier emits a next value.
    If the source observable errors and the notifier completes, it will complete the source sequence.

    - seealso: [retry operator on reactivex.io](http://reactivex.io/documentation/operators/retry.html)
    
    - parameter notificationHandler: A handler that is passed an observable sequence of errors raised by the source observable and returns and observable that either continues, completes or errors. This behavior is then applied to the source observable.
    - returns: An observable sequence producing the elements of the given sequence repeatedly until it terminates successfully or is notified to error or complete.
    */
    public func retryWhen<TriggerObservable: ObservableType>(_ notificationHandler: @escaping (Observable<Swift.Error>) -> TriggerObservable)
        -> Observable<E> {
            return RetryWhenSequence(sources: InfiniteSequence(repeatedValue: self.asObservable()), notificationHandler: notificationHandler)
    }
}

// MARK: scan

extension ObservableType {
    
    /**
    Applies an accumulator function over an observable sequence and returns each intermediate result. The specified seed value is used as the initial accumulator value.

    For aggregation behavior with no intermediate results, see `reduce`.

    - seealso: [scan operator on reactivex.io](http://reactivex.io/documentation/operators/scan.html)
    
    - parameter seed: The initial accumulator value.
    - parameter accumulator: An accumulator function to be invoked on each element.
    - returns: An observable sequence containing the accumulated values.
    */
    public func scan<A>(_ seed: A, accumulator: @escaping (A, E) throws -> A)
        -> Observable<A> {
        return Scan(source: self.asObservable(), seed: seed, accumulator: accumulator)
    }
}
