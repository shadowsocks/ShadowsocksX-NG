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
    public func scan<A>(into seed: A, accumulator: @escaping (inout A, Element) throws -> Void)
        -> Observable<A> {
        Scan(source: self.asObservable(), seed: seed, accumulator: accumulator)
    }

    /**
     Applies an accumulator function over an observable sequence and returns each intermediate result. The specified seed value is used as the initial accumulator value.

     For aggregation behavior with no intermediate results, see `reduce`.

     - seealso: [scan operator on reactivex.io](http://reactivex.io/documentation/operators/scan.html)

     - parameter seed: The initial accumulator value.
     - parameter accumulator: An accumulator function to be invoked on each element.
     - returns: An observable sequence containing the accumulated values.
     */
    public func scan<A>(_ seed: A, accumulator: @escaping (A, Element) throws -> A)
        -> Observable<A> {
        return Scan(source: self.asObservable(), seed: seed) { acc, element in
            let currentAcc = acc
            acc = try accumulator(currentAcc, element)
        }
    }
}

final private class ScanSink<Element, Observer: ObserverType>: Sink<Observer>, ObserverType {
    typealias Accumulate = Observer.Element 
    typealias Parent = Scan<Element, Accumulate>

    private let parent: Parent
    private var accumulate: Accumulate
    
    init(parent: Parent, observer: Observer, cancel: Cancelable) {
        self.parent = parent
        self.accumulate = parent.seed
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<Element>) {
        switch event {
        case .next(let element):
            do {
                try self.parent.accumulator(&self.accumulate, element)
                self.forwardOn(.next(self.accumulate))
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
    
    private let source: Observable<Element>
    fileprivate let seed: Accumulate
    fileprivate let accumulator: Accumulator
    
    init(source: Observable<Element>, seed: Accumulate, accumulator: @escaping Accumulator) {
        self.source = source
        self.seed = seed
        self.accumulator = accumulator
    }
    
    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == Accumulate {
        let sink = ScanSink(parent: self, observer: observer, cancel: cancel)
        let subscription = self.source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
