//
//  Create.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 2/8/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension Observable {
    // MARK: create

    /**
     Creates an observable sequence from a specified subscribe method implementation.

     - seealso: [create operator on reactivex.io](http://reactivex.io/documentation/operators/create.html)

     - parameter subscribe: Implementation of the resulting observable sequence's `subscribe` method.
     - returns: The observable sequence with the specified implementation for the `subscribe` method.
     */
    public static func create(_ subscribe: @escaping (AnyObserver<E>) -> Disposable) -> Observable<E> {
        return AnonymousObservable(subscribe)
    }
}

final fileprivate class AnonymousObservableSink<O: ObserverType> : Sink<O>, ObserverType {
    typealias E = O.E
    typealias Parent = AnonymousObservable<E>

    // state
    private var _isStopped: AtomicInt = 0

    #if DEBUG
        fileprivate let _synchronizationTracker = SynchronizationTracker()
    #endif

    override init(observer: O, cancel: Cancelable) {
        super.init(observer: observer, cancel: cancel)
    }

    func on(_ event: Event<E>) {
        #if DEBUG
            _synchronizationTracker.register(synchronizationErrorMessage: .default)
            defer { _synchronizationTracker.unregister() }
        #endif
        switch event {
        case .next:
            if _isStopped == 1 {
                return
            }
            forwardOn(event)
        case .error, .completed:
            if AtomicCompareAndSwap(0, 1, &_isStopped) {
                forwardOn(event)
                dispose()
            }
        }
    }

    func run(_ parent: Parent) -> Disposable {
        return parent._subscribeHandler(AnyObserver(self))
    }
}

final fileprivate class AnonymousObservable<Element> : Producer<Element> {
    typealias SubscribeHandler = (AnyObserver<Element>) -> Disposable

    let _subscribeHandler: SubscribeHandler

    init(_ subscribeHandler: @escaping SubscribeHandler) {
        _subscribeHandler = subscribeHandler
    }

    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        let sink = AnonymousObservableSink(observer: observer, cancel: cancel)
        let subscription = sink.run(self)
        return (sink: sink, subscription: subscription)
    }
}
