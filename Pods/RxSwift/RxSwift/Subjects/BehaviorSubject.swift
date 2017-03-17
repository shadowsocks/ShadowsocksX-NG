//
//  BehaviorSubject.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 5/23/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

/// Represents a value that changes over time.
///
/// Observers can subscribe to the subject to receive the last (or initial) value and all subsequent notifications.
public final class BehaviorSubject<Element>
    : Observable<Element>
    , SubjectType
    , ObserverType
    , SynchronizedUnsubscribeType
    , Disposable {
    public typealias SubjectObserverType = BehaviorSubject<Element>
    typealias DisposeKey = Bag<AnyObserver<Element>>.KeyType
    
    /// Indicates whether the subject has any observers
    public var hasObservers: Bool {
        _lock.lock(); defer { _lock.unlock() }
        return _observers.count > 0
    }
    
    let _lock = NSRecursiveLock()
    
    // state
    private var _isDisposed = false
    private var _value: Element
    private var _observers = Bag<AnyObserver<Element>>()
    private var _stoppedEvent: Event<Element>?

    /// Indicates whether the subject has been disposed.
    public var isDisposed: Bool {
        return _isDisposed
    }
 
    /// Initializes a new instance of the subject that caches its last value and starts with the specified value.
    ///
    /// - parameter value: Initial value sent to observers when no other value has been received by the subject yet.
    public init(value: Element) {
        _value = value
    }
    
    /// Gets the current value or throws an error.
    ///
    /// - returns: Latest value.
    public func value() throws -> Element {
        _lock.lock(); defer { _lock.unlock() } // {
            if _isDisposed {
                throw RxError.disposed(object: self)
            }
            
            if let error = _stoppedEvent?.error {
                // intentionally throw exception
                throw error
            }
            else {
                return _value
            }
        //}
    }
    
    /// Notifies all subscribed observers about next event.
    ///
    /// - parameter event: Event to send to the observers.
    public func on(_ event: Event<E>) {
        _synchronized_on(event).on(event)
    }

    func _synchronized_on(_ event: Event<E>) -> Bag<AnyObserver<Element>> {
        _lock.lock(); defer { _lock.unlock() }
        if _stoppedEvent != nil || _isDisposed {
            return Bag()
        }
        
        switch event {
        case .next(let value):
            _value = value
        case .error, .completed:
            _stoppedEvent = event
        }
        
        return _observers
    }
    
    /// Subscribes an observer to the subject.
    ///
    /// - parameter observer: Observer to subscribe to the subject.
    /// - returns: Disposable object that can be used to unsubscribe the observer from the subject.
    public override func subscribe<O : ObserverType>(_ observer: O) -> Disposable where O.E == Element {
        _lock.lock(); defer { _lock.unlock() }
        return _synchronized_subscribe(observer)
    }

    func _synchronized_subscribe<O : ObserverType>(_ observer: O) -> Disposable where O.E == E {
        if _isDisposed {
            observer.on(.error(RxError.disposed(object: self)))
            return Disposables.create()
        }
        
        if let stoppedEvent = _stoppedEvent {
            observer.on(stoppedEvent)
            return Disposables.create()
        }
        
        let key = _observers.insert(observer.asObserver())
        observer.on(.next(_value))
    
        return SubscriptionDisposable(owner: self, key: key)
    }

    func synchronizedUnsubscribe(_ disposeKey: DisposeKey) {
        _lock.lock(); defer { _lock.unlock() }
        _synchronized_unsubscribe(disposeKey)
    }

    func _synchronized_unsubscribe(_ disposeKey: DisposeKey) {
        if _isDisposed {
            return
        }

        _ = _observers.removeKey(disposeKey)
    }

    /// Returns observer interface for subject.
    public func asObserver() -> BehaviorSubject<Element> {
        return self
    }

    /// Unsubscribe all observers and release resources.
    public func dispose() {
        _lock.performLocked {
            _isDisposed = true
            _observers.removeAll()
            _stoppedEvent = nil
        }
    }
}
