//
//  Scan.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 6/14/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {

    /**
     Applies an accumulator function over an observable sequence and returns each intermediate result. The specified seed value is used as the initial accumulator value.

     For aggregation behavior with no intermediate results, see `reduce`.

     - seealso: [scan operator on reactivex.io](http://reactivex.io/documentation/operators/scan.html)

     - parameter seed: The initial accumulator value.
     - parameter accumulator: An accumulator function to be invoked on each element.
     - returns: An observable sequence containing the accumulated values.
     */
    public func scan<A>(into seed: A, accumulator: @escaping (inout A, E) throws -> Void)
        -> Observable<A> {
        return Scan(source: self.asObservable(), seed: seed, accumulator: accumulator)
    }

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
        return Scan(source: self.asObservable(), seed: seed) { acc, element in
            let currentAcc = acc
            acc = try accumulator(currentAcc, element)
        }
    }
}

final private class ScanSink<ElementType, O: ObserverType>: Sink<O>, ObserverType {
    typealias Accumulate = O.E
    typealias Parent = Scan<ElementType, Accumulate>
    typealias E = ElementType
    
    fileprivate let _parent: Parent
    fileprivate var _accumulate: Accumulate
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        self._parent = parent
        self._accumulate = parent._seed
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<ElementType>) {
        switch event {
        case .next(let element):
            do {
                try self._parent._accumulator(&self._accumulate, element)
                self.forwardOn(.next(self._accumulate))
            }
            catch let error {
                self.forwardOn(.error(error))
                self.dispose()
            }
        case .error(let error):
            self.forwardOn(.error(error))
            self.dispose()
        case .completed:
            self.forwardOn(.completed)
            self.dispose()
        }
    }
    
}

final private class Scan<Element, Accumulate>: Producer<Accumulate> {
    typealias Accumulator = (inout Accumulate, Element) throws -> Void
    
    fileprivate let _source: Observable<Element>
    fileprivate let _seed: Accumulate
    fileprivate let _accumulator: Accumulator
    
    init(source: Observable<Element>, seed: Accumulate, accumulator: @escaping Accumulator) {
        self._source = source
        self._seed = seed
        self._accumulator = accumulator
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Accumulate {
        let sink = ScanSink(parent: self, observer: observer, cancel: cancel)
        let subscription = self._source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
