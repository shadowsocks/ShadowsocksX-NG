//
//  Sink.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 2/19/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

class Sink<O : ObserverType> : Disposable {
    fileprivate let _observer: O
    fileprivate let _cancel: Cancelable
    fileprivate var _disposed: Bool

    init(observer: O, cancel: Cancelable) {
#if TRACE_RESOURCES
        let _ = Resources.incrementTotal()
#endif
        _observer = observer
        _cancel = cancel
        _disposed = false
    }
    
    final func forwardOn(_ event: Event<O.E>) {
        if _disposed {
            return
        }
        _observer.on(event)
    }
    
    final func forwarder() -> SinkForward<O> {
        return SinkForward(forward: self)
    }

    var disposed: Bool {
        return _disposed
    }

    func dispose() {
        _disposed = true
        _cancel.dispose()
    }

    deinit {
#if TRACE_RESOURCES
       let _ =  Resources.decrementTotal()
#endif
    }
}

class SinkForward<O: ObserverType>: ObserverType {
    typealias E = O.E
    
    private let _forward: Sink<O>
    
    init(forward: Sink<O>) {
        _forward = forward
    }
    
    func on(_ event: Event<E>) {
        switch event {
        case .next:
            _forward._observer.on(event)
        case .error, .completed:
            _forward._observer.on(event)
            _forward._cancel.dispose()
        }
    }
}
