//
//  ShareReplay1WhileConnected.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 12/6/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

fileprivate final class ShareReplay1WhileConnectedConnection<Element>
    : ObserverType
    , SynchronizedUnsubscribeType {
    typealias E = Element
    typealias Observers = AnyObserver<Element>.s
    typealias DisposeKey = Observers.KeyType

    typealias Parent = ShareReplay1WhileConnected<Element>
    private let _parent: Parent
    private let _subscription = SingleAssignmentDisposable()

    private let _lock: RecursiveLock
    private var _disposed: Bool = false
    fileprivate var _observers = Observers()
    fileprivate var _element: Element?

    init(parent: Parent, lock: RecursiveLock) {
        _parent = parent
        _lock = lock

        #if TRACE_RESOURCES
            _ = Resources.incrementTotal()
        #endif
    }

    final func on(_ event: Event<E>) {
        _lock.lock()
        let observers = _synchronized_on(event)
        _lock.unlock()
        dispatch(observers, event)
    }

    final private func _synchronized_on(_ event: Event<E>) -> Observers {
        if _disposed {
            return Observers()
        }

        switch event {
        case .next(let element):
            _element = element
            return _observers
        case .error, .completed:
            let observers = _observers
            self._synchronized_dispose()
            return observers
        }
    }

    final func connect() {
        _subscription.setDisposable(_parent._source.subscribe(self))
    }

    final func _synchronized_subscribe<O : ObserverType>(_ observer: O) -> Disposable where O.E == Element {
        _lock.lock(); defer { _lock.unlock() }
        if let element = _element {
            observer.on(.next(element))
        }

        let disposeKey = _observers.insert(observer.on)

        return SubscriptionDisposable(owner: self, key: disposeKey)
    }

    final private func _synchronized_dispose() {
        _disposed = true
        if _parent._connection === self {
            _parent._connection = nil
        }
        _observers = Observers()
        _subscription.dispose()
    }

    final func synchronizedUnsubscribe(_ disposeKey: DisposeKey) {
        _lock.lock()
        _synchronized_unsubscribe(disposeKey)
        _lock.unlock()
    }

    @inline(__always)
    final private func _synchronized_unsubscribe(_ disposeKey: DisposeKey) {
        // if already unsubscribed, just return
        if self._observers.removeKey(disposeKey) == nil {
            return
        }

        if _observers.count == 0 {
            _synchronized_dispose()
        }
    }

    #if TRACE_RESOURCES
        deinit {
            _ = Resources.decrementTotal()
        }
    #endif
}

// optimized version of share replay for most common case
final class ShareReplay1WhileConnected<Element>
    : Observable<Element> {

    fileprivate typealias Connection = ShareReplay1WhileConnectedConnection<Element>

    fileprivate let _source: Observable<Element>

    fileprivate let _lock = RecursiveLock()

    fileprivate var _connection: Connection?

    init(source: Observable<Element>) {
        self._source = source
    }

    override func subscribe<O : ObserverType>(_ observer: O) -> Disposable where O.E == E {
        _lock.lock()

        let connection = _synchronized_subscribe(observer)
        let count = connection._observers.count

        let disposable = connection._synchronized_subscribe(observer)
        
        if count == 0 {
            connection.connect()
        }

        _lock.unlock()

        return disposable
    }

    @inline(__always)
    private func _synchronized_subscribe<O : ObserverType>(_ observer: O) -> Connection where O.E == E {
        let connection: Connection

        if let existingConnection = _connection {
            connection = existingConnection
        }
        else {
            connection = ShareReplay1WhileConnectedConnection<Element>(
                parent: self,
                lock: _lock)
            _connection = connection
        }

        return connection
    }
}
