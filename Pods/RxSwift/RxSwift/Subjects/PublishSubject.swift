//
//  PublishSubject.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 2/11/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

/// Represents an object that is both an observable sequence as well as an observer.
///
/// Each notification is broadcasted to all subscribed observers.
public final class PublishSubject<Element>
    : Observable<Element>
    , SubjectType
    , Cancelable
    , ObserverType
    , SynchronizedUnsubscribeType {
    public typealias SubjectObserverType = PublishSubject<Element>

    typealias Observers = AnyObserver<Element>.s
    typealias DisposeKey = Observers.KeyType
    
    /// Indicates whether the subject has any observers
    public var hasObservers: Bool {
        self._lock.lock()
        let count = self._observers.count > 0
        self._lock.unlock()
        return count
    }
    
    private let _lock = RecursiveLock()
    
    // state
    private var _isDisposed = false
    private var _observers = Observers()
    private var _stopped = false
    private var _stoppedEvent = nil as Event<Element>?

    #if DEBUG
        fileprivate let _synchronizationTracker = SynchronizationTracker()
    #endif

    /// Indicates whether the subject has been isDisposed.
    public var isDisposed: Bool {
        return self._isDisposed
    }
    
    /// Creates a subject.
    public override init() {
        super.init()
        #if TRACE_RESOURCES
            _ = Resources.incrementTotal()
        #endif
    }
    
    /// Notifies all subscribed observers about next event.
    ///
    /// - parameter event: Event to send to the observers.
    public func on(_ event: Event<Element>) {
        #if DEBUG
            self._synchronizationTracker.register(synchronizationErrorMessage: .default)
            defer { self._synchronizationTracker.unregister() }
        #endif
        dispatch(self._synchronized_on(event), event)
    }

    func _synchronized_on(_ event: Event<E>) -> Observers {
        self._lock.lock(); defer { self._lock.unlock() }
        switch event {
        case .next:
            if self._isDisposed || self._stopped {
                return Observers()
            }
            
            return self._observers
        case .completed, .error:
            if self._stoppedEvent == nil {
                self._stoppedEvent = event
                self._stopped = true
                let observers = self._observers
                self._observers.removeAll()
                return observers
            }

            return Observers()
        }
    }
    
    /**
    Subscribes an observer to the subject.
    
    - parameter observer: Observer to subscribe to the subject.
    - returns: Disposable object that can be used to unsubscribe the observer from the subject.
    */
    public override func subscribe<O: ObserverType>(_ observer: O) -> Disposable where O.E == Element {
        self._lock.lock()
        let subscription = self._synchronized_subscribe(observer)
        self._lock.unlock()
        return subscription
    }

    func _synchronized_subscribe<O: ObserverType>(_ observer: O) -> Disposable where O.E == E {
        if let stoppedEvent = self._stoppedEvent {
            observer.on(stoppedEvent)
            return Disposables.create()
        }
        
        if self._isDisposed {
            observer.on(.error(RxError.disposed(object: self)))
            return Disposables.create()
        }
        
        let key = self._observers.insert(observer.on)
        return SubscriptionDisposable(owner: self, key: key)
    }

    func synchronizedUnsubscribe(_ disposeKey: DisposeKey) {
        self._lock.lock()
        self._synchronized_unsubscribe(disposeKey)
        self._lock.unlock()
    }

    func _synchronized_unsubscribe(_ disposeKey: DisposeKey) {
        _ = self._observers.removeKey(disposeKey)
    }
    
    /// Returns observer interface for subject.
    public func asObserver() -> PublishSubject<Element> {
        return self
    }
    
    /// Unsubscribe all observers and release resources.
    public func dispose() {
        self._lock.lock()
        self._synchronized_dispose()
        self._lock.unlock()
    }

    final func _synchronized_dispose() {
        self._isDisposed = true
        self._observers.removeAll()
        self._stoppedEvent = nil
    }

    #if TRACE_RESOURCES
        deinit {
            _ = Resources.decrementTotal()
        }
    #endif
}
