//
//  Do.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 2/21/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {
    /**
     Invokes an action for each event in the observable sequence, and propagates all observer messages through the result sequence.

     - seealso: [do operator on reactivex.io](http://reactivex.io/documentation/operators/do.html)

     - parameter onNext: Action to invoke for each element in the observable sequence.
     - parameter onError: Action to invoke upon errored termination of the observable sequence.
     - parameter onCompleted: Action to invoke upon graceful termination of the observable sequence.
     - parameter onSubscribe: Action to invoke before subscribing to source observable sequence.
     - parameter onSubscribed: Action to invoke after subscribing to source observable sequence.
     - parameter onDispose: Action to invoke after subscription to source observable has been disposed for any reason. It can be either because sequence terminates for some reason or observer subscription being disposed.
     - returns: The source sequence with the side-effecting behavior applied.
     */
    public func `do`(onNext: ((E) throws -> Void)? = nil, onError: ((Swift.Error) throws -> Void)? = nil, onCompleted: (() throws -> Void)? = nil, onSubscribe: (() -> Void)? = nil, onSubscribed: (() -> Void)? = nil, onDispose: (() -> Void)? = nil)
        -> Observable<E> {
            return Do(source: self.asObservable(), eventHandler: { e in
                switch e {
                case .next(let element):
                    try onNext?(element)
                case .error(let e):
                    try onError?(e)
                case .completed:
                    try onCompleted?()
                }
            }, onSubscribe: onSubscribe, onSubscribed: onSubscribed, onDispose: onDispose)
    }
}

final private class DoSink<O: ObserverType>: Sink<O>, ObserverType {
    typealias Element = O.E
    typealias EventHandler = (Event<Element>) throws -> Void
    
    private let _eventHandler: EventHandler
    
    init(eventHandler: @escaping EventHandler, observer: O, cancel: Cancelable) {
        self._eventHandler = eventHandler
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<Element>) {
        do {
            try self._eventHandler(event)
            self.forwardOn(event)
            if event.isStopEvent {
                self.dispose()
            }
        }
        catch let error {
            self.forwardOn(.error(error))
            self.dispose()
        }
    }
}

final private class Do<Element>: Producer<Element> {
    typealias EventHandler = (Event<Element>) throws -> Void
    
    fileprivate let _source: Observable<Element>
    fileprivate let _eventHandler: EventHandler
    fileprivate let _onSubscribe: (() -> Void)?
    fileprivate let _onSubscribed: (() -> Void)?
    fileprivate let _onDispose: (() -> Void)?
    
    init(source: Observable<Element>, eventHandler: @escaping EventHandler, onSubscribe: (() -> Void)?, onSubscribed: (() -> Void)?, onDispose: (() -> Void)?) {
        self._source = source
        self._eventHandler = eventHandler
        self._onSubscribe = onSubscribe
        self._onSubscribed = onSubscribed
        self._onDispose = onDispose
    }
    
    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        self._onSubscribe?()
        let sink = DoSink(eventHandler: self._eventHandler, observer: observer, cancel: cancel)
        let subscription = self._source.subscribe(sink)
        self._onSubscribed?()
        let onDispose = self._onDispose
        let allSubscriptions = Disposables.create {
            subscription.dispose()
            onDispose?()
        }
        return (sink: sink, subscription: allSubscriptions)
    }
}
