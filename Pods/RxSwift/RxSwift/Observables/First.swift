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
            forwardOn(.next(value))
            forwardOn(.completed)
            dispose()
        case .error(let error):
            forwardOn(.error(error))
            dispose()
        case .completed:
            forwardOn(.next(nil))
            forwardOn(.completed)
            dispose()
        }
    }
}

final class First<Element>: Producer<Element?> {
    fileprivate let _source: Observable<Element>

    init(source: Observable<Element>) {
        _source = source
    }

    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element? {
        let sink = FirstSink(observer: observer, cancel: cancel)
        let subscription = _source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
