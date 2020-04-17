//
//  AsyncSubject.swift
//  RxSwift
//
//  Created by Victor Galán on 07/01/2017.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

/// An AsyncSubject emits the last value (and only the last value) emitted by the source Observable,
/// and only after that source Observable completes.
///
/// (If the source Observable does not emit any values, the AsyncSubject also completes without emitting any values.)
public final class AsyncSubject<Element>
    : Observable<Element>
    , SubjectType
    , ObserverType
    , SynchronizedUnsubscribeType {
    public typealias SubjectObserverType = AsyncSubject<Element>

    typealias Observers = AnyObserver<Element>.s
    typealias DisposeKey = Observers.KeyType

    /// Indicates whether the subject has any observers
    public var hasObservers: Bool {
        self._lock.lock(); defer { self._lock.unlock() }
        return self._observers.count > 0
    }

    let _lock = RecursiveLock()

    // state
    private var _observers = Observers()
    private var _isStopped = false
    private var _stoppedEvent = nil as Event<Element>? {
        didSet {
            self._isStopped = self._stoppedEvent != nil
        }
    }
    private var _lastElement: Element?

    #if DEBUG
        private let _synchronizationTracker = SynchronizationTracker()
    #endif


    /// Creates a subject.
    public override init() {
        #if TRACE_RESOURCES
            _ = Resources.incrementTotal()
        #endif
        super.init()
    }

    /// Notifies all subscribed observers about next event.
    ///
    /// - parameter event: Event to send to the observers.
    public func on(_ event: Event<Element>) {
        #if DEBUG
            self._synchronizationTracker.register(synchronizationErrorMessage: .default)
            defer { self._synchronizationTracker.unregister() }
        #endif
        let (observers, event) = self._synchronized_on(event)
        switch event {
        case .next:
            dispatch(observers, event)
            dispatch(observers, .completed)
        case .completed:
            dispatch(observers, event)
        case .error:
            dispatch(observers, event)
        }
    }

    func _synchronized_on(_ event: Event<Element>) -> (Observers, Event<Element>) {
        self._lock.lock(); defer { self._lock.unlock() }
        if self._isStopped {
            return (Observers(), .completed)
        }

        switch event {
        case .next(let element):
            self._lastElement = element
            return (Observers(), .completed)
        case .error:
            self._stoppedEvent = event

            let observers = self._observers
            self._observers.removeAll()

            return (observers, event)
        case .completed:

            let observers = self._observers
            self._observers.removeAll()

            if let lastElement = self._lastElement {
                self._stoppedEvent = .next(lastElement)
                return (observers, .next(lastElement))
            }
            else {
                self._stoppedEvent = event
                return (observers, .completed)
            }
        }
    }

    /// Subscribes an observer to the subject.
    ///
    /// - parameter observer: Observer to subscribe to the subject.
    /// - returns: Disposable object that can be used to unsubscribe the observer from the subject.
    public override func subscribe<Observer: ObserverType>(_ observer: Observer) -> Disposable where Observer.Element == Element {
        self._lock.lock(); defer { self._lock.unlock() }
        return self._synchronized_subscribe(observer)
    }

    func _synchronized_subscribe<Observer: ObserverType>(_ observer: Observer) -> Disposable where Observer.Element == Element {
        if let stoppedEvent = self._stoppedEvent {
            switch stoppedEvent {
            case .next:
                observer.on(stoppedEvent)
                observer.on(.completed)
            case .completed:
                observer.on(stoppedEvent)
            case .error:
                observer.on(stoppedEvent)
            }
            return Disposables.create()
        }

        let key = self._observers.insert(observer.on)

        return SubscriptionDisposable(owner: self, key: key)
    }

    func synchronizedUnsubscribe(_ disposeKey: DisposeKey) {
        self._lock.lock(); defer { self._lock.unlock() }
        self._synchronized_unsubscribe(disposeKey)
    }
    
    func _synchronized_unsubscribe(_ disposeKey: DisposeKey) {
        _ = self._observers.removeKey(disposeKey)
    }
    
    /// Returns observer interface for subject.
    public func asObserver() -> AsyncSubject<Element> {
        return self
    }

    #if TRACE_RESOURCES
    deinit {
        _ = Resources.decrementTotal()
    }
    #endif
}

