//
//  Reduce.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 4/1/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

final class ReduceSink<SourceType, AccumulateType, O: ObserverType> : Sink<O>, ObserverType {
    typealias ResultType = O.E
    typealias Parent = Reduce<SourceType, AccumulateType, ResultType>
    
    private let _parent: Parent
    private var _accumulation: AccumulateType
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        _parent = parent
        _accumulation = parent._seed
        
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<SourceType>) {
        switch event {
        case .next(let value):
            do {
                _accumulation = try _parent._accumulator(_accumulation, value)
            }
            catch let e {
                forwardOn(.error(e))
                dispose()
            }
        case .error(let e):
            forwardOn(.error(e))
            dispose()
        case .completed:
            do {
                let result = try _parent._mapResult(_accumulation)
                forwardOn(.next(result))
                forwardOn(.completed)
                dispose()
            }
            catch let e {
                forwardOn(.error(e))
                dispose()
            }
        }
    }
}

final class Reduce<SourceType, AccumulateType, ResultType> : Producer<ResultType> {
    typealias AccumulatorType = (AccumulateType, SourceType) throws -> AccumulateType
    typealias ResultSelectorType = (AccumulateType) throws -> ResultType
    
    fileprivate let _source: Observable<SourceType>
    fileprivate let _seed: AccumulateType
    fileprivate let _accumulator: AccumulatorType
    fileprivate let _mapResult: ResultSelectorType
    
    init(source: Observable<SourceType>, seed: AccumulateType, accumulator: @escaping AccumulatorType, mapResult: @escaping ResultSelectorType) {
        _source = source
        _seed = seed
        _accumulator = accumulator
        _mapResult = mapResult
    }

    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == ResultType {
        let sink = ReduceSink(parent: self, observer: observer, cancel: cancel)
        let subscription = _source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
