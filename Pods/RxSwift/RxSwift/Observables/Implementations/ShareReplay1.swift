//
//  ShareReplay1.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 10/10/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

// optimized version of share replay for most common case
final class ShareReplay1<Element>
    : Observable<Element>
    , ObserverType
    , SynchronizedUnsubscribeType {

    typealias Observers = AnyObserver<Element>.s
    typealias DisposeKey = Observers.KeyType

    private let _source: Observable<Element>

    private let _lock = RecursiveLock()

    private var _connection: SingleAssignmentDisposable?
    private var _element: Element?
    private var _stopped = false
    private var _stopEvent = nil as Event<Element>?
    private var _observers = Observers()

    init(source: Observable<Element>) {
        self._source = source
    }

    override func subscribe<O : ObserverType>(_ observer: O) -> Disposable where O.E == E {
        _lock.lock()
        let result = _synchronized_subscribe(observer)
        _lock.unlock()
        return result
    }

    func _synchronized_subscribe<O : ObserverType>(_ observer: O) -> Disposable where O.E == E {
        if let element = self._element {
            observer.on(.next(element))
        }

        if let stopEvent = self._stopEvent {
            observer.on(stopEvent)
            return Disposables.create()
        }

        let initialCount = self._observers.count

        let disposeKey = self._observers.insert(observer.on)

        if initialCount == 0 {
            let connection = SingleAssignmentDisposable()
            _connection = connection

            connection.setDisposable(self._source.subscribe(self))
        }

        return SubscriptionDisposable(owner: self, key: disposeKey)
    }

    func synchronizedUnsubscribe(_ disposeKey: DisposeKey) {
        _lock.lock()
        _synchronized_unsubscribe(disposeKey)
        _lock.unlock()
    }

    func _synchronized_unsubscribe(_ disposeKey: DisposeKey) {
        // if already unsubscribed, just return
        if self._observers.removeKey(disposeKey) == nil {
            return
        }

        if _observers.count == 0 {
            _connection?.dispose()
            _connection = nil
        }
    }

    func on(_ event: Event<E>) {
        dispatch(_synchronized_on(event), event)
    }

    func _synchronized_on(_ event: Event<E>) -> Observers {
        _lock.lock(); defer { _lock.unlock() }
        if _stopped {
            return Observers()
        }

        switch event {
        case .next(let element):
            _element = element
        case .error, .completed:
            _stopEvent = event
            _stopped = true
            _connection?.dispose()
            _connection = nil
        }
        
        return _observers
    }
    
}
