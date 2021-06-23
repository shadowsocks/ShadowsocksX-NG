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
        self.lock.performLocked { self.observers.count > 0 }
    }
    
    private let lock = RecursiveLock()
    
    // state
    private var disposed = false
    private var observers = Observers()
    private var stopped = false
    private var stoppedEvent = nil as Event<Element>?

    #if DEBUG
        private let synchronizationTracker = SynchronizationTracker()
    #endif

    /// Indicates whether the subject has been isDisposed.
    public var isDisposed: Bool {
        self.disposed
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
            self.synchronizationTracker.register(synchronizationErrorMessage: .default)
            defer { self.synchronizationTracker.unregister() }
        #endif
        dispatch(self.synchronized_on(event), event)
    }

    func synchronized_on(_ event: Event<Element>) -> Observers {
        self.lock.lock(); defer { self.lock.unlock() }
        switch event {
        case .next:
            if self.isDisposed || self.stopped {
                return Observers()
            }
            
            return self.observers
        case .completed, .error:
            if self.stoppedEvent == nil {
                self.stoppedEvent = event
                self.stopped = true
                let observers = self.observers
                self.observers.removeAll()
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
    public override func subscribe<Observer: ObserverType>(_ observer: Observer) -> Disposable where Observer.Element == Element {
        self.lock.performLocked { self.synchronized_subscribe(observer) }
    }

    func synchronized_subscribe<Observer: ObserverType>(_ observer: Observer) -> Disposable where Observer.Element == Element {
        if let stoppedEvent = self.stoppedEvent {
            observer.on(stoppedEvent)
            return Disposables.create()
        }
        
        if self.isDisposed {
            observer.on(.error(RxError.disposed(object: self)))
            return Disposables.create()
        }
        
        let key = self.observers.insert(observer.on)
        return SubscriptionDisposable(owner: self, key: key)
    }

    func synchronizedUnsubscribe(_ disposeKey: DisposeKey) {
        self.lock.performLocked { self.synchronized_unsubscribe(disposeKey) }
    }

    func synchronized_unsubscribe(_ disposeKey: DisposeKey) {
        _ = self.observers.removeKey(disposeKey)
    }
    
    /// Returns observer interface for subject.
    public func asObserver() -> PublishSubject<Element> {
        self
    }
    
    /// Unsubscribe all observers and release resources.
    public func dispose() {
        self.lock.performLocked { self.synchronized_dispose() }
    }

    final func synchronized_dispose() {
        self.disposed = true
        self.observers.removeAll()
        self.stoppedEvent = nil
    }

    #if TRACE_RESOURCES
        deinit {
            _ = Resources.decrementTotal()
        }
    #endif
}
