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
        self.lock.performLocked {
            self.observers.count > 0
        }
    }

    let lock = RecursiveLock()

    // state
    private var observers = Observers()
    private var isStopped = false
    private var stoppedEvent = nil as Event<Element>? {
        didSet {
            self.isStopped = self.stoppedEvent != nil
        }
    }
    private var lastElement: Element?

    #if DEBUG
        private let synchronizationTracker = SynchronizationTracker()
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
            self.synchronizationTracker.register(synchronizationErrorMessage: .default)
            defer { self.synchronizationTracker.unregister() }
        #endif
        let (observers, event) = self.synchronized_on(event)
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

    func synchronized_on(_ event: Event<Element>) -> (Observers, Event<Element>) {
        self.lock.lock(); defer { self.lock.unlock() }
        if self.isStopped {
            return (Observers(), .completed)
        }

        switch event {
        case .next(let element):
            self.lastElement = element
            return (Observers(), .completed)
        case .error:
            self.stoppedEvent = event

            let observers = self.observers
            self.observers.removeAll()

            return (observers, event)
        case .completed:

            let observers = self.observers
            self.observers.removeAll()

            if let lastElement = self.lastElement {
                self.stoppedEvent = .next(lastElement)
                return (observers, .next(lastElement))
            }
            else {
                self.stoppedEvent = event
                return (observers, .completed)
            }
        }
    }

    /// Subscribes an observer to the subject.
    ///
    /// - parameter observer: Observer to subscribe to the subject.
    /// - returns: Disposable object that can be used to unsubscribe the observer from the subject.
    public override func subscribe<Observer: ObserverType>(_ observer: Observer) -> Disposable where Observer.Element == Element {
        self.lock.performLocked { self.synchronized_subscribe(observer) }
    }

    func synchronized_subscribe<Observer: ObserverType>(_ observer: Observer) -> Disposable where Observer.Element == Element {
        if let stoppedEvent = self.stoppedEvent {
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
    public func asObserver() -> AsyncSubject<Element> {
        self
    }

    #if TRACE_RESOURCES
    deinit {
        _ = Resources.decrementTotal()
    }
    #endif
}

