//
//  AsMaybe.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/12/17.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

private final class AsMaybeSink<Observer: ObserverType> : Sink<Observer>, ObserverType {
    typealias Element = Observer.Element

    private var _element: Event<Element>?

    func on(_ event: Event<Element>) {
        switch event {
        case .next:
            if self._element != nil {
                self.forwardOn(.error(RxError.moreThanOneElement))
                self.dispose()
            }

            self._element = event
        case .error:
            self.forwardOn(event)
            self.dispose()
        case .completed:
            if let element = self._element {
                self.forwardOn(element)
            }
            self.forwardOn(.completed)
            self.dispose()
        }
    }
}

final class AsMaybe<Element>: Producer<Element> {
    private let _source: Observable<Element>

    init(source: Observable<Element>) {
        self._source = source
    }

    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == Element {
        let sink = AsMaybeSink(observer: observer, cancel: cancel)
        let subscription = self._source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
