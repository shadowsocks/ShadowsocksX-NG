//
//  Sink.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 2/19/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

class Sink<O : ObserverType> : Disposable {
    fileprivate let _observer: O
    fileprivate let _cancel: Cancelable
    fileprivate let _disposed = AtomicInt(0)

    #if DEBUG
        fileprivate let _synchronizationTracker = SynchronizationTracker()
    #endif

    init(observer: O, cancel: Cancelable) {
#if TRACE_RESOURCES
        _ = Resources.incrementTotal()
#endif
        self._observer = observer
        self._cancel = cancel
    }

    final func forwardOn(_ event: Event<O.E>) {
        #if DEBUG
            self._synchronizationTracker.register(synchronizationErrorMessage: .default)
            defer { self._synchronizationTracker.unregister() }
        #endif
        if isFlagSet(self._disposed, 1) {
            return
        }
        self._observer.on(event)
    }

    final func forwarder() -> SinkForward<O> {
        return SinkForward(forward: self)
    }

    final var disposed: Bool {
        return isFlagSet(self._disposed, 1)
    }

    func dispose() {
        fetchOr(self._disposed, 1)
        self._cancel.dispose()
    }

    deinit {
#if TRACE_RESOURCES
       _ =  Resources.decrementTotal()
#endif
    }
}

final class SinkForward<O: ObserverType>: ObserverType {
    typealias E = O.E

    private let _forward: Sink<O>

    init(forward: Sink<O>) {
        self._forward = forward
    }

    final func on(_ event: Event<E>) {
        switch event {
        case .next:
            self._forward._observer.on(event)
        case .error, .completed:
            self._forward._observer.on(event)
            self._forward._cancel.dispose()
        }
    }
}
