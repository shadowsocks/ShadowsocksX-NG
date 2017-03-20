//
//  Observable+Aggregate.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/22/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

// MARK: reduce

extension ObservableType {
    
    /**
    Applies an `accumulator` function over an observable sequence, returning the result of the aggregation as a single element in the result sequence. The specified `seed` value is used as the initial accumulator value.

    For aggregation behavior with incremental intermediate results, see `scan`.

    - seealso: [reduce operator on reactivex.io](http://reactivex.io/documentation/operators/reduce.html)

    - parameter seed: The initial accumulator value.
    - parameter accumulator: A accumulator function to be invoked on each element.
    - parameter mapResult: A function to transform the final accumulator value into the result value.
    - returns: An observable sequence containing a single element with the final accumulator value.
    */
    public func reduce<A, R>(_ seed: A, accumulator: @escaping (A, E) throws -> A, mapResult: @escaping (A) throws -> R)
        -> Observable<R> {
        return Reduce(source: self.asObservable(), seed: seed, accumulator: accumulator, mapResult: mapResult)
    }

    /**
    Applies an `accumulator` function over an observable sequence, returning the result of the aggregation as a single element in the result sequence. The specified `seed` value is used as the initial accumulator value.
    
    For aggregation behavior with incremental intermediate results, see `scan`.

    - seealso: [reduce operator on reactivex.io](http://reactivex.io/documentation/operators/reduce.html)
    
    - parameter seed: The initial accumulator value.
    - parameter accumulator: A accumulator function to be invoked on each element.
    - returns: An observable sequence containing a single element with the final accumulator value.
    */
    public func reduce<A>(_ seed: A, accumulator: @escaping (A, E) throws -> A)
        -> Observable<A> {
        return Reduce(source: self.asObservable(), seed: seed, accumulator: accumulator, mapResult: { $0 })
    }

    /**
    Converts an Observable into another Observable that emits the whole sequence as a single array and then terminates.
    
    For aggregation behavior see `reduce`.

    - seealso: [toArray operator on reactivex.io](http://reactivex.io/documentation/operators/to.html)
    
    - returns: An observable sequence containing all the emitted elements as array.
    */
    public func toArray()
        -> Observable<[E]> {
            return ToArray(source: self.asObservable())
    }
}
