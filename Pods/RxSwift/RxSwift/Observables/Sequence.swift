//
//  Sequence.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 11/14/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension Observable {
    // MARK: of

    /**
     This method creates a new Observable instance with a variable number of elements.

     - seealso: [from operator on reactivex.io](http://reactivex.io/documentation/operators/from.html)

     - parameter elements: Elements to generate.
     - parameter scheduler: Scheduler to send elements on. If `nil`, elements are sent immediately on subscription.
     - returns: The observable sequence whose elements are pulled from the given arguments.
     */
    public static func of(_ elements: E ..., scheduler: ImmediateSchedulerType = CurrentThreadScheduler.instance) -> Observable<E> {
        return ObservableSequence(elements: elements, scheduler: scheduler)
    }
}

extension Observable {
    /**
     Converts an array to an observable sequence.

     - seealso: [from operator on reactivex.io](http://reactivex.io/documentation/operators/from.html)

     - returns: The observable sequence whose elements are pulled from the given enumerable sequence.
     */
    public static func from(_ array: [E], scheduler: ImmediateSchedulerType = CurrentThreadScheduler.instance) -> Observable<E> {
        return ObservableSequence(elements: array, scheduler: scheduler)
    }

    /**
     Converts a sequence to an observable sequence.

     - seealso: [from operator on reactivex.io](http://reactivex.io/documentation/operators/from.html)

     - returns: The observable sequence whose elements are pulled from the given enumerable sequence.
     */
    public static func from<S: Sequence>(_ sequence: S, scheduler: ImmediateSchedulerType = CurrentThreadScheduler.instance) -> Observable<E> where S.Iterator.Element == E {
        return ObservableSequence(elements: sequence, scheduler: scheduler)
    }
}

final fileprivate class ObservableSequenceSink<S: Sequence, O: ObserverType> : Sink<O> where S.Iterator.Element == O.E {
    typealias Parent = ObservableSequence<S>

    private let _parent: Parent

    init(parent: Parent, observer: O, cancel: Cancelable) {
        _parent = parent
        super.init(observer: observer, cancel: cancel)
    }

    func run() -> Disposable {
        return _parent._scheduler.scheduleRecursive((_parent._elements.makeIterator(), _parent._elements)) { (iterator, recurse) in
            var mutableIterator = iterator
            if let next = mutableIterator.0.next() {
                self.forwardOn(.next(next))
                recurse(mutableIterator)
            }
            else {
                self.forwardOn(.completed)
                self.dispose()
            }
        }
    }
}

final fileprivate class ObservableSequence<S: Sequence> : Producer<S.Iterator.Element> {
    fileprivate let _elements: S
    fileprivate let _scheduler: ImmediateSchedulerType

    init(elements: S, scheduler: ImmediateSchedulerType) {
        _elements = elements
        _scheduler = scheduler
    }

    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == E {
        let sink = ObservableSequenceSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}
