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
        _lock.lock(); defer { _lock.unlock() }
        return _observers.count > 0
    }

    let _lock = RecursiveLock()

    // state
    private var _observers = Observers()
    private var _isStopped = false
    private var _stoppedEvent = nil as Event<Element>? {
        didSet {
            _isStopped = _stoppedEvent != nil
        }
    }
    private var _lastElement: Element?

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
    public func on(_ event: Event<E>) {
        let (observers, event) = _synchronized_on(event)
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

    func _synchronized_on(_ event: Event<E>) -> (Observers, Event<E>) {
        _lock.lock(); defer { _lock.unlock() }
        if _isStopped {
            return (Observers(), .completed)
        }

        switch event {
        case .next(let element):
            _lastElement = element
            return (Observers(), .completed)
        case .error:
            _stoppedEvent = event

            let observers = _observers
            _observers.removeAll()

            return (observers, event)
        case .completed:

            let observers = _observers
            _observers.removeAll()

            if let lastElement = _lastElement {
                _stoppedEvent = .next(lastElement)
                return (observers, .next(lastElement))
            }
            else {
                _stoppedEvent = event
                return (observers, .completed)
            }
        }
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
        if let stoppedEvent = _stoppedEvent {
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

        let key = _observers.insert(observer.on)

        return SubscriptionDisposable(owner: self, key: key)
    }

    func synchronizedUnsubscribe(_ disposeKey: DisposeKey) {
        _lock.lock(); defer { _lock.unlock() }
        _synchronized_unsubscribe(disposeKey)
    }
    
    func _synchronized_unsubscribe(_ disposeKey: DisposeKey) {
        _ = _observers.removeKey(disposeKey)
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

