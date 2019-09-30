//
//  Materialize.swift
//  RxSwift
//
//  Created by sergdort on 08/03/2017.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {
    /**
     Convert any Observable into an Observable of its events.
     - seealso: [materialize operator on reactivex.io](http://reactivex.io/documentation/operators/materialize-dematerialize.html)
     - returns: An observable sequence that wraps events in an Event<E>. The returned Observable never errors, but it does complete after observing all of the events of the underlying Observable.
     */
    public func materialize() -> Observable<Event<E>> {
        return Materialize(source: self.asObservable())
    }
}

fileprivate final class MaterializeSink<Element, O: ObserverType>: Sink<O>, ObserverType where O.E == Event<Element> {
    
    func on(_ event: Event<Element>) {
        self.forwardOn(.next(event))
        if event.isStopEvent {
            self.forwardOn(.completed)
            self.dispose()
        }
    }
}

final private class Materialize<Element>: Producer<Event<Element>> {
    private let _source: Observable<Element>
    
    init(source: Observable<Element>) {
        self._source = source
    }

    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == E {
        let sink = MaterializeSink(observer: observer, cancel: cancel)
        let subscription = self._source.subscribe(sink)

        return (sink: sink, subscription: subscription)
    }
}
