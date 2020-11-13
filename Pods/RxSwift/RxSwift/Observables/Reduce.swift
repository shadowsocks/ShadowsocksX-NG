//
//  Reduce.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 4/1/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//


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
    public func reduce<A, Result>(_ seed: A, accumulator: @escaping (A, Element) throws -> A, mapResult: @escaping (A) throws -> Result)
        -> Observable<Result> {
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
    public func reduce<A>(_ seed: A, accumulator: @escaping (A, Element) throws -> A)
        -> Observable<A> {
        return Reduce(source: self.asObservable(), seed: seed, accumulator: accumulator, mapResult: { $0 })
    }
}

final private class ReduceSink<SourceType, AccumulateType, Observer: ObserverType>: Sink<Observer>, ObserverType {
    typealias ResultType = Observer.Element 
    typealias Parent = Reduce<SourceType, AccumulateType, ResultType>
    
    private let _parent: Parent
    private var _accumulation: AccumulateType
    
    init(parent: Parent, observer: Observer, cancel: Cancelable) {
        self._parent = parent
        self._accumulation = parent._seed
        
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<SourceType>) {
        switch event {
        case .next(let value):
            do {
                self._accumulation = try self._parent._accumulator(self._accumulation, value)
            }
            catch let e {
                self.forwardOn(.error(e))
                self.dispose()
            }
        case .error(let e):
            self.forwardOn(.error(e))
            self.dispose()
        case .completed:
            do {
                let result = try self._parent._mapResult(self._accumulation)
                self.forwardOn(.next(result))
                self.forwardOn(.completed)
                self.dispose()
            }
            catch let e {
                self.forwardOn(.error(e))
                self.dispose()
            }
        }
    }
}

final private class Reduce<SourceType, AccumulateType, ResultType>: Producer<ResultType> {
    typealias AccumulatorType = (AccumulateType, SourceType) throws -> AccumulateType
    typealias ResultSelectorType = (AccumulateType) throws -> ResultType
    
    private let _source: Observable<SourceType>
    fileprivate let _seed: AccumulateType
    fileprivate let _accumulator: AccumulatorType
    fileprivate let _mapResult: ResultSelectorType
    
    init(source: Observable<SourceType>, seed: AccumulateType, accumulator: @escaping AccumulatorType, mapResult: @escaping ResultSelectorType) {
        self._source = source
        self._seed = seed
        self._accumulator = accumulator
        self._mapResult = mapResult
    }

    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == ResultType {
        let sink = ReduceSink(parent: self, observer: observer, cancel: cancel)
        let subscription = self._source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}

