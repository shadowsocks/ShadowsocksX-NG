//
//  Sequence.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 11/14/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

class ObservableSequenceSink<S: Sequence, O: ObserverType> : Sink<O> where S.Iterator.Element == O.E {
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
            }
        }
    }
}

class ObservableSequence<S: Sequence> : Producer<S.Iterator.Element> {
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
