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
        _lock.lock()
        let count = _observers.count > 0
        _lock.unlock()
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
        return _isDisposed
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
            _synchronizationTracker.register(synchronizationErrorMessage: .default)
            defer { _synchronizationTracker.unregister() }
        #endif
        dispatch(_synchronized_on(event), event)
    }

    func _synchronized_on(_ event: Event<E>) -> Observers {
        _lock.lock(); defer { _lock.unlock() }
        switch event {
        case .next(_):
            if _isDisposed || _stopped {
                return Observers()
            }
            
            return _observers
        case .completed, .error:
            if _stoppedEvent == nil {
                _stoppedEvent = event
                _stopped = true
                let observers = _observers
                _observers.removeAll()
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
    public override func subscribe<O : ObserverType>(_ observer: O) -> Disposable where O.E == Element {
        _lock.lock()
        let subscription = _synchronized_subscribe(observer)
        _lock.unlock()
        return subscription
    }

    func _synchronized_subscribe<O : ObserverType>(_ observer: O) -> Disposable where O.E == E {
        if let stoppedEvent = _stoppedEvent {
            observer.on(stoppedEvent)
            return Disposables.create()
        }
        
        if _isDisposed {
            observer.on(.error(RxError.disposed(object: self)))
            return Disposables.create()
        }
        
        let key = _observers.insert(observer.on)
        return SubscriptionDisposable(owner: self, key: key)
    }

    func synchronizedUnsubscribe(_ disposeKey: DisposeKey) {
        _lock.lock()
        _synchronized_unsubscribe(disposeKey)
        _lock.unlock()
    }

    func _synchronized_unsubscribe(_ disposeKey: DisposeKey) {
        _ = _observers.removeKey(disposeKey)
    }
    
    /// Returns observer interface for subject.
    public func asObserver() -> PublishSubject<Element> {
        return self
    }
    
    /// Unsubscribe all observers and release resources.
    public func dispose() {
        _lock.lock()
        _synchronized_dispose()
        _lock.unlock()
    }

    final func _synchronized_dispose() {
        _isDisposed = true
        _observers.removeAll()
        _stoppedEvent = nil
    }

    #if TRACE_RESOURCES
        deinit {
            _ = Resources.decrementTotal()
        }
    #endif
}
