//
//  First.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 7/31/17.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

fileprivate final class FirstSink<Element, O: ObserverType> : Sink<O>, ObserverType where O.E == Element? {
    typealias E = Element
    typealias Parent = First<E>

    func on(_ event: Event<E>) {
        switch event {
        case .next(let value):
            self.forwardOn(.next(value))
            self.forwardOn(.completed)
            self.dispose()
        case .error(let error):
            self.forwardOn(.error(error))
            self.dispose()
        case .completed:
            self.forwardOn(.next(nil))
            self.forwardOn(.completed)
            self.dispose()
        }
    }
}

final class First<Element>: Producer<Element?> {
    fileprivate let _source: Observable<Element>

    init(source: Observable<Element>) {
        self._source = source
    }

    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element? {
        let sink = FirstSink(observer: observer, cancel: cancel)
        let subscription = self._source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
