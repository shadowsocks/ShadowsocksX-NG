//
//  Range.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 9/13/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType where E : RxAbstractInteger {
    /**
     Generates an observable sequence of integral numbers within a specified range, using the specified scheduler to generate and send out observer messages.

     - seealso: [range operator on reactivex.io](http://reactivex.io/documentation/operators/range.html)

     - parameter start: The value of the first integer in the sequence.
     - parameter count: The number of sequential integers to generate.
     - parameter scheduler: Scheduler to run the generator loop on.
     - returns: An observable sequence that contains a range of sequential integral numbers.
     */
    public static func range(start: E, count: E, scheduler: ImmediateSchedulerType = CurrentThreadScheduler.instance) -> Observable<E> {
        return RangeProducer<E>(start: start, count: count, scheduler: scheduler)
    }
}

final fileprivate class RangeProducer<E: RxAbstractInteger> : Producer<E> {
    fileprivate let _start: E
    fileprivate let _count: E
    fileprivate let _scheduler: ImmediateSchedulerType

    init(start: E, count: E, scheduler: ImmediateSchedulerType) {
        if count < 0 {
            rxFatalError("count can't be negative")
        }

        if start &+ (count - 1) < start {
            rxFatalError("overflow of count")
        }

        _start = start
        _count = count
        _scheduler = scheduler
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == E {
        let sink = RangeSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}

final fileprivate class RangeSink<O: ObserverType> : Sink<O> where O.E: RxAbstractInteger {
    typealias Parent = RangeProducer<O.E>
    
    private let _parent: Parent
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        _parent = parent
        super.init(observer: observer, cancel: cancel)
    }
    
    func run() -> Disposable {
        return _parent._scheduler.scheduleRecursive(0 as O.E) { i, recurse in
            if i < self._parent._count {
                self.forwardOn(.next(self._parent._start + i))
                recurse(i + 1)
            }
            else {
                self.forwardOn(.completed)
                self.dispose()
            }
        }
    }
}
