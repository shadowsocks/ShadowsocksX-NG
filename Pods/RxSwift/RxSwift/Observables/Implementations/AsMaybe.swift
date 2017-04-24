//
//  AsMaybe.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/12/17.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

fileprivate final class AsMaybeSink<O: ObserverType> : Sink<O>, ObserverType {
    typealias ElementType = O.E
    typealias E = ElementType

    private var _element: Event<E>? = nil

    func on(_ event: Event<E>) {
        switch event {
        case .next:
            if _element != nil {
                forwardOn(.error(RxError.moreThanOneElement))
                dispose()
            }

            _element = event
        case .error:
            forwardOn(event)
            dispose()
        case .completed:
            if let element = _element {
                forwardOn(element)
            }
            forwardOn(.completed)
            dispose()
        }
    }
}

final class AsMaybe<Element>: Producer<Element> {
    fileprivate let _source: Observable<Element>

    init(source: Observable<Element>) {
        _source = source
    }

    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        let sink = AsMaybeSink(observer: observer, cancel: cancel)
        let subscription = _source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
