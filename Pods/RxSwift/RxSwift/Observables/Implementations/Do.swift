//
//  Do.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 2/21/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

final class DoSink<O: ObserverType> : Sink<O>, ObserverType {
    typealias Element = O.E
    typealias Parent = Do<Element>
    
    private let _parent: Parent
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        _parent = parent
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<Element>) {
        do {
            try _parent._eventHandler(event)
            forwardOn(event)
            if event.isStopEvent {
                dispose()
            }
        }
        catch let error {
            forwardOn(.error(error))
            dispose()
        }
    }
}

final class Do<Element> : Producer<Element> {
    typealias EventHandler = (Event<Element>) throws -> Void
    
    fileprivate let _source: Observable<Element>
    fileprivate let _eventHandler: EventHandler
    fileprivate let _onSubscribe: (() -> ())?
    fileprivate let _onSubscribed: (() -> ())?
    fileprivate let _onDispose: (() -> ())?
    
    init(source: Observable<Element>, eventHandler: @escaping EventHandler, onSubscribe: (() -> ())?, onSubscribed: (() -> ())?, onDispose: (() -> ())?) {
        _source = source
        _eventHandler = eventHandler
        _onSubscribe = onSubscribe
        _onSubscribed = onSubscribed
        _onDispose = onDispose
    }
    
    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        _onSubscribe?()
        let sink = DoSink(parent: self, observer: observer, cancel: cancel)
        let subscription = _source.subscribe(sink)
        _onSubscribed?()
        let onDispose = _onDispose
        let allSubscriptions = Disposables.create {
            subscription.dispose()
            onDispose?()
        }
        return (sink: sink, subscription: allSubscriptions)
    }
}
