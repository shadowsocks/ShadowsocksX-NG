//
//  Dematerialize.swift
//  RxSwift
//
//  Created by Jamie Pinkham on 3/13/17.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

extension ObservableType where E: EventConvertible {
    /**
     Convert any previously materialized Observable into it's original form.
     - seealso: [materialize operator on reactivex.io](http://reactivex.io/documentation/operators/materialize-dematerialize.html)
     - returns: The dematerialized observable sequence.
     */
    public func dematerialize() -> Observable<E.ElementType> {
        return Dematerialize(source: self.asObservable())
    }

}

fileprivate final class DematerializeSink<Element: EventConvertible, O: ObserverType>: Sink<O>, ObserverType where O.E == Element.ElementType {
    fileprivate func on(_ event: Event<Element>) {
        switch event {
        case .next(let element):
            forwardOn(element.event)
            if element.event.isStopEvent {
                dispose()
            }
        case .completed:
            forwardOn(.completed)
            dispose()
        case .error(let error):
            forwardOn(.error(error))
            dispose()
        }
    }
}

final fileprivate class Dematerialize<Element: EventConvertible>: Producer<Element.ElementType>  {
    private let _source: Observable<Element>
    
    init(source: Observable<Element>) {
        _source = source
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element.ElementType {
        let sink = DematerializeSink<Element, O>(observer: observer, cancel: cancel)
        let subscription = _source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
