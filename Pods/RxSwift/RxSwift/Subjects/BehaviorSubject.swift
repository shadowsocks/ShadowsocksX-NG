//
//  BehaviorSubject.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 5/23/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

/// Represents a value that changes over time.
///
/// Observers can subscribe to the subject to receive the last (or initial) value and all subsequent notifications.
public final class BehaviorSubject<Element>
    : Observable<Element>
    , SubjectType
    , ObserverType
    , SynchronizedUnsubscribeType
    , Cancelable {
    public typealias SubjectObserverType = BehaviorSubject<Element>

    typealias Observers = AnyObserver<Element>.s
    typealias DisposeKey = Observers.KeyType
    
    /// Indicates whether the subject has any observers
    public var hasObservers: Bool {
        self._lock.lock()
        let value = self._observers.count > 0
        self._lock.unlock()
        return value
    }
    
    let _lock = RecursiveLock()
    
    // state
    private var _isDisposed = false
    private var _element: Element
    private var _observers = Observers()
    private var _stoppedEvent: Event<Element>?

    #if DEBUG
        fileprivate let _synchronizationTracker = SynchronizationTracker()
    #endif

    /// Indicates whether the subject has been disposed.
    public var isDisposed: Bool {
        return self._isDisposed
    }
 
    /// Initializes a new instance of the subject that caches its last value and starts with the specified value.
    ///
    /// - parameter value: Initial value sent to observers when no other value has been received by the subject yet.
    public init(value: Element) {
        self._element = value

        #if TRACE_RESOURCES
            _ = Resources.incrementTotal()
        #endif
    }
    
    /// Gets the current value or throws an error.
    ///
    /// - returns: Latest value.
    public func value() throws -> Element {
        self._lock.lock(); defer { self._lock.unlock() } // {
            if self._isDisposed {
                throw RxError.disposed(object: self)
            }
            
            if let error = self._stoppedEvent?.error {
                // intentionally throw exception
                throw error
            }
            else {
                return self._element
            }
        //}
    }
    
    /// Notifies all subscribed observers about next event.
    ///
    /// - parameter event: Event to send to the observers.
    public func on(_ event: Event<E>) {
        #if DEBUG
            self._synchronizationTracker.register(synchronizationErrorMessage: .default)
            defer { self._synchronizationTracker.unregister() }
        #endif
        dispatch(self._synchronized_on(event), event)
    }

    func _synchronized_on(_ event: Event<E>) -> Observers {
        self._lock.lock(); defer { self._lock.unlock() }
        if self._stoppedEvent != nil || self._isDisposed {
            return Observers()
        }
        
        switch event {
        case .next(let element):
            self._element = element
        case .error, .completed:
            self._stoppedEvent = event
        }
        
        return self._observers
    }
    
    /// Subscribes an observer to the subject.
    ///
    /// - parameter observer: Observer to subscribe to the subject.
    /// - returns: Disposable object that can be used to unsubscribe the observer from the subject.
    public override func subscribe<O: ObserverType>(_ observer: O) -> Disposable where O.E == Element {
        self._lock.lock()
        let subscription = self._synchronized_subscribe(observer)
        self._lock.unlock()
        return subscription
    }

    func _synchronized_subscribe<O: ObserverType>(_ observer: O) -> Disposable where O.E == E {
        if self._isDisposed {
            observer.on(.error(RxError.disposed(object: self)))
            return Disposables.create()
        }
        
        if let stoppedEvent = self._stoppedEvent {
            observer.on(stoppedEvent)
            return Disposables.create()
        }
        
        let key = self._observers.insert(observer.on)
        observer.on(.next(self._element))
    
        return SubscriptionDisposable(owner: self, key: key)
    }

    func synchronizedUnsubscribe(_ disposeKey: DisposeKey) {
        self._lock.lock()
        self._synchronized_unsubscribe(disposeKey)
        self._lock.unlock()
    }

    func _synchronized_unsubscribe(_ disposeKey: DisposeKey) {
        if self._isDisposed {
            return
        }

        _ = self._observers.removeKey(disposeKey)
    }

    /// Returns observer interface for subject.
    public func asObserver() -> BehaviorSubject<Element> {
        return self
    }

    /// Unsubscribe all observers and release resources.
    public func dispose() {
        self._lock.lock()
        self._isDisposed = true
        self._observers.removeAll()
        self._stoppedEvent = nil
        self._lock.unlock()
    }

    #if TRACE_RESOURCES
        deinit {
        _ = Resources.decrementTotal()
        }
    #endif
}
