//
//  ReplaySubject.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 4/14/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

/// Represents an object that is both an observable sequence as well as an observer.
///
/// Each notification is broadcasted to all subscribed and future observers, subject to buffer trimming policies.
public class ReplaySubject<Element>
    : Observable<Element>
    , SubjectType
    , ObserverType
    , Disposable {
    public typealias SubjectObserverType = ReplaySubject<Element>

    typealias Observers = AnyObserver<Element>.s
    typealias DisposeKey = Observers.KeyType

    /// Indicates whether the subject has any observers
    public var hasObservers: Bool {
        self._lock.lock()
        let value = self._observers.count > 0
        self._lock.unlock()
        return value
    }
    
    fileprivate let _lock = RecursiveLock()
    
    // state
    fileprivate var _isDisposed = false
    fileprivate var _isStopped = false
    fileprivate var _stoppedEvent = nil as Event<Element>? {
        didSet {
            self._isStopped = self._stoppedEvent != nil
        }
    }
    fileprivate var _observers = Observers()

    #if DEBUG
        fileprivate let _synchronizationTracker = SynchronizationTracker()
    #endif

    func unsubscribe(_ key: DisposeKey) {
        rxAbstractMethod()
    }

    final var isStopped: Bool {
        return self._isStopped
    }
    
    /// Notifies all subscribed observers about next event.
    ///
    /// - parameter event: Event to send to the observers.
    public func on(_ event: Event<E>) {
        rxAbstractMethod()
    }
    
    /// Returns observer interface for subject.
    public func asObserver() -> SubjectObserverType {
        return self
    }
    
    /// Unsubscribe all observers and release resources.
    public func dispose() {
    }

    /// Creates new instance of `ReplaySubject` that replays at most `bufferSize` last elements of sequence.
    ///
    /// - parameter bufferSize: Maximal number of elements to replay to observer after subscription.
    /// - returns: New instance of replay subject.
    public static func create(bufferSize: Int) -> ReplaySubject<Element> {
        if bufferSize == 1 {
            return ReplayOne()
        }
        else {
            return ReplayMany(bufferSize: bufferSize)
        }
    }

    /// Creates a new instance of `ReplaySubject` that buffers all the elements of a sequence.
    /// To avoid filling up memory, developer needs to make sure that the use case will only ever store a 'reasonable'
    /// number of elements.
    public static func createUnbounded() -> ReplaySubject<Element> {
        return ReplayAll()
    }

    #if TRACE_RESOURCES
        override init() {
            _ = Resources.incrementTotal()
        }

        deinit {
            _ = Resources.decrementTotal()
        }
    #endif
}

private class ReplayBufferBase<Element>
    : ReplaySubject<Element>
    , SynchronizedUnsubscribeType {
    
    func trim() {
        rxAbstractMethod()
    }
    
    func addValueToBuffer(_ value: Element) {
        rxAbstractMethod()
    }
    
    func replayBuffer<O: ObserverType>(_ observer: O) where O.E == Element {
        rxAbstractMethod()
    }
    
    override func on(_ event: Event<Element>) {
        #if DEBUG
            self._synchronizationTracker.register(synchronizationErrorMessage: .default)
            defer { self._synchronizationTracker.unregister() }
        #endif
        dispatch(self._synchronized_on(event), event)
    }

    func _synchronized_on(_ event: Event<E>) -> Observers {
        self._lock.lock(); defer { self._lock.unlock() }
        if self._isDisposed {
            return Observers()
        }
        
        if self._isStopped {
            return Observers()
        }
        
        switch event {
        case .next(let element):
            self.addValueToBuffer(element)
            self.trim()
            return self._observers
        case .error, .completed:
            self._stoppedEvent = event
            self.trim()
            let observers = self._observers
            self._observers.removeAll()
            return observers
        }
    }
    
    override func subscribe<O: ObserverType>(_ observer: O) -> Disposable where O.E == Element {
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
     
        let anyObserver = observer.asObserver()
        
        self.replayBuffer(anyObserver)
        if let stoppedEvent = self._stoppedEvent {
            observer.on(stoppedEvent)
            return Disposables.create()
        }
        else {
            let key = self._observers.insert(observer.on)
            return SubscriptionDisposable(owner: self, key: key)
        }
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
    
    override func dispose() {
        super.dispose()

        self.synchronizedDispose()
    }

    func synchronizedDispose() {
        self._lock.lock()
        self._synchronized_dispose()
        self._lock.unlock()
    }

    func _synchronized_dispose() {
        self._isDisposed = true
        self._observers.removeAll()
    }
}

fileprivate final class ReplayOne<Element> : ReplayBufferBase<Element> {
    private var _value: Element?
    
    override init() {
        super.init()
    }
    
    override func trim() {
        
    }
    
    override func addValueToBuffer(_ value: Element) {
        self._value = value
    }

    override func replayBuffer<O: ObserverType>(_ observer: O) where O.E == Element {
        if let value = self._value {
            observer.on(.next(value))
        }
    }

    override func _synchronized_dispose() {
        super._synchronized_dispose()
        self._value = nil
    }
}

private class ReplayManyBase<Element>: ReplayBufferBase<Element> {
    fileprivate var _queue: Queue<Element>
    
    init(queueSize: Int) {
        self._queue = Queue(capacity: queueSize + 1)
    }
    
    override func addValueToBuffer(_ value: Element) {
        self._queue.enqueue(value)
    }

    override func replayBuffer<O: ObserverType>(_ observer: O) where O.E == Element {
        for item in self._queue {
            observer.on(.next(item))
        }
    }

    override func _synchronized_dispose() {
        super._synchronized_dispose()
        self._queue = Queue(capacity: 0)
    }
}

fileprivate final class ReplayMany<Element> : ReplayManyBase<Element> {
    private let _bufferSize: Int
    
    init(bufferSize: Int) {
        self._bufferSize = bufferSize
        
        super.init(queueSize: bufferSize)
    }
    
    override func trim() {
        while self._queue.count > self._bufferSize {
            _ = self._queue.dequeue()
        }
    }
}

fileprivate final class ReplayAll<Element> : ReplayManyBase<Element> {
    init() {
        super.init(queueSize: 0)
    }
    
    override func trim() {
        
    }
}
