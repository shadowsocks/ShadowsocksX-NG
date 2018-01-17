//
//  Producer.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 2/20/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

class Producer<Element> : Observable<Element> {
    override init() {
        super.init()
    }
    
    override func subscribe<O : ObserverType>(_ observer: O) -> Disposable where O.E == Element {
        if !CurrentThreadScheduler.isScheduleRequired {
            // The returned disposable needs to release all references once it was disposed.
            let disposer = SinkDisposer()
            let sinkAndSubscription = run(observer, cancel: disposer)
            disposer.setSinkAndSubscription(sink: sinkAndSubscription.sink, subscription: sinkAndSubscription.subscription)

            return disposer
        }
        else {
            return CurrentThreadScheduler.instance.schedule(()) { _ in
                let disposer = SinkDisposer()
                let sinkAndSubscription = self.run(observer, cancel: disposer)
                disposer.setSinkAndSubscription(sink: sinkAndSubscription.sink, subscription: sinkAndSubscription.subscription)

                return disposer
            }
        }
    }
    
    func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        rxAbstractMethod()
    }
}

fileprivate final class SinkDisposer: Cancelable {
    fileprivate enum DisposeState: UInt32 {
        case disposed = 1
        case sinkAndSubscriptionSet = 2
    }

    // Jeej, swift API consistency rules
    fileprivate enum DisposeStateInt32: Int32 {
        case disposed = 1
        case sinkAndSubscriptionSet = 2
    }
    
    private var _state: AtomicInt = 0
    private var _sink: Disposable? = nil
    private var _subscription: Disposable? = nil

    var isDisposed: Bool {
        return AtomicFlagSet(DisposeState.disposed.rawValue, &_state)
    }

    func setSinkAndSubscription(sink: Disposable, subscription: Disposable) {
        _sink = sink
        _subscription = subscription

        let previousState = AtomicOr(DisposeState.sinkAndSubscriptionSet.rawValue, &_state)
        if (previousState & DisposeStateInt32.sinkAndSubscriptionSet.rawValue) != 0 {
            rxFatalError("Sink and subscription were already set")
        }

        if (previousState & DisposeStateInt32.disposed.rawValue) != 0 {
            sink.dispose()
            subscription.dispose()
            _sink = nil
            _subscription = nil
        }
    }
    
    func dispose() {
        let previousState = AtomicOr(DisposeState.disposed.rawValue, &_state)

        if (previousState & DisposeStateInt32.disposed.rawValue) != 0 {
            return
        }

        if (previousState & DisposeStateInt32.sinkAndSubscriptionSet.rawValue) != 0 {
            guard let sink = _sink else {
                rxFatalError("Sink not set")
            }
            guard let subscription = _subscription else {
                rxFatalError("Subscription not set")
            }

            sink.dispose()
            subscription.dispose()

            _sink = nil
            _subscription = nil
        }
    }
}
