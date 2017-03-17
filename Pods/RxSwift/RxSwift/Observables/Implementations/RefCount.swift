//
//  RefCount.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/5/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

class RefCountSink<CO: ConnectableObservableType, O: ObserverType>
    : Sink<O>
    , ObserverType where CO.E == O.E {
    typealias Element = O.E
    typealias Parent = RefCount<CO>
    
    private let _parent: Parent

    init(parent: Parent, observer: O, cancel: Cancelable) {
        _parent = parent
        super.init(observer: observer, cancel: cancel)
    }
    
    func run() -> Disposable {
        let subscription = _parent._source.subscribeSafe(self)
        
        _parent._lock.lock(); defer { _parent._lock.unlock() } // {
            if _parent._count == 0 {
                _parent._count = 1
                _parent._connectableSubscription = _parent._source.connect()
            }
            else {
                _parent._count = _parent._count + 1
            }
        // }
        
        return Disposables.create {
            subscription.dispose()
            self._parent._lock.lock(); defer { self._parent._lock.unlock() } // {
                if self._parent._count == 1 {
                    self._parent._connectableSubscription!.dispose()
                    self._parent._count = 0
                    self._parent._connectableSubscription = nil
                }
                else if self._parent._count > 1 {
                    self._parent._count = self._parent._count - 1
                }
                else {
                    rxFatalError("Something went wrong with RefCount disposing mechanism")
                }
            // }
        }
    }

    func on(_ event: Event<Element>) {
        switch event {
        case .next:
            forwardOn(event)
        case .error, .completed:
            forwardOn(event)
            dispose()
        }
    }
}

class RefCount<CO: ConnectableObservableType>: Producer<CO.E> {
    fileprivate let _lock = NSRecursiveLock()
    
    // state
    fileprivate var _count = 0
    fileprivate var _connectableSubscription = nil as Disposable?
    
    fileprivate let _source: CO
    
    init(source: CO) {
        _source = source
    }
    
    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == CO.E {
        let sink = RefCountSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}
