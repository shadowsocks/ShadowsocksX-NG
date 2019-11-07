//
//  Multicast.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 2/27/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

/**
 Represents an observable wrapper that can be connected and disconnected from its underlying observable sequence.
 */
public class ConnectableObservable<Element>
    : Observable<Element>
    , ConnectableObservableType {

    /**
     Connects the observable wrapper to its source. All subscribed observers will receive values from the underlying observable sequence as long as the connection is established.

     - returns: Disposable used to disconnect the observable wrapper from its source, causing subscribed observer to stop receiving values from the underlying observable sequence.
     */
    public func connect() -> Disposable {
        rxAbstractMethod()
    }
}

extension ObservableType {

    /**
    Multicasts the source sequence notifications through an instantiated subject into all uses of the sequence within a selector function.

    Each subscription to the resulting sequence causes a separate multicast invocation, exposing the sequence resulting from the selector function's invocation.

    For specializations with fixed subject types, see `publish` and `replay`.

    - seealso: [multicast operator on reactivex.io](http://reactivex.io/documentation/operators/publish.html)

    - parameter subjectSelector: Factory function to create an intermediate subject through which the source sequence's elements will be multicast to the selector function.
    - parameter selector: Selector function which can use the multicasted source sequence subject to the policies enforced by the created subject.
    - returns: An observable sequence that contains the elements of a sequence produced by multicasting the source sequence within a selector function.
    */
    public func multicast<S: SubjectType, R>(_ subjectSelector: @escaping () throws -> S, selector: @escaping (Observable<S.E>) throws -> Observable<R>)
        -> Observable<R> where S.SubjectObserverType.E == E {
        return Multicast(
            source: self.asObservable(),
            subjectSelector: subjectSelector,
            selector: selector
        )
    }
}

extension ObservableType {

    /**
    Returns a connectable observable sequence that shares a single subscription to the underlying sequence.

    This operator is a specialization of `multicast` using a `PublishSubject`.

    - seealso: [publish operator on reactivex.io](http://reactivex.io/documentation/operators/publish.html)

    - returns: A connectable observable sequence that shares a single subscription to the underlying sequence.
    */
    public func publish() -> ConnectableObservable<E> {
        return self.multicast { PublishSubject() }
    }
}

extension ObservableType {

    /**
     Returns a connectable observable sequence that shares a single subscription to the underlying sequence replaying bufferSize elements.

     This operator is a specialization of `multicast` using a `ReplaySubject`.

     - seealso: [replay operator on reactivex.io](http://reactivex.io/documentation/operators/replay.html)

     - parameter bufferSize: Maximum element count of the replay buffer.
     - returns: A connectable observable sequence that shares a single subscription to the underlying sequence.
     */
    public func replay(_ bufferSize: Int)
        -> ConnectableObservable<E> {
        return self.multicast { ReplaySubject.create(bufferSize: bufferSize) }
    }

    /**
     Returns a connectable observable sequence that shares a single subscription to the underlying sequence replaying all elements.

     This operator is a specialization of `multicast` using a `ReplaySubject`.

     - seealso: [replay operator on reactivex.io](http://reactivex.io/documentation/operators/replay.html)

     - returns: A connectable observable sequence that shares a single subscription to the underlying sequence.
     */
    public func replayAll()
        -> ConnectableObservable<E> {
        return self.multicast { ReplaySubject.createUnbounded() }
    }
}

extension ConnectableObservableType {

    /**
    Returns an observable sequence that stays connected to the source as long as there is at least one subscription to the observable sequence.

    - seealso: [refCount operator on reactivex.io](http://reactivex.io/documentation/operators/refcount.html)

    - returns: An observable sequence that stays connected to the source as long as there is at least one subscription to the observable sequence.
    */
    public func refCount() -> Observable<E> {
        return RefCount(source: self)
    }
}

extension ObservableType {

    /**
     Multicasts the source sequence notifications through the specified subject to the resulting connectable observable.

     Upon connection of the connectable observable, the subject is subscribed to the source exactly one, and messages are forwarded to the observers registered with the connectable observable.

     For specializations with fixed subject types, see `publish` and `replay`.

     - seealso: [multicast operator on reactivex.io](http://reactivex.io/documentation/operators/publish.html)

     - parameter subject: Subject to push source elements into.
     - returns: A connectable observable sequence that upon connection causes the source sequence to push results into the specified subject.
     */
    public func multicast<S: SubjectType>(_ subject: S)
        -> ConnectableObservable<S.E> where S.SubjectObserverType.E == E {
        return ConnectableObservableAdapter(source: self.asObservable(), makeSubject: { subject })
    }

    /**
     Multicasts the source sequence notifications through an instantiated subject to the resulting connectable observable.

     Upon connection of the connectable observable, the subject is subscribed to the source exactly one, and messages are forwarded to the observers registered with the connectable observable.

     Subject is cleared on connection disposal or in case source sequence produces terminal event.

     - seealso: [multicast operator on reactivex.io](http://reactivex.io/documentation/operators/publish.html)

     - parameter makeSubject: Factory function used to instantiate a subject for each connection.
     - returns: A connectable observable sequence that upon connection causes the source sequence to push results into the specified subject.
     */
    public func multicast<S: SubjectType>(makeSubject: @escaping () -> S)
        -> ConnectableObservable<S.E> where S.SubjectObserverType.E == E {
        return ConnectableObservableAdapter(source: self.asObservable(), makeSubject: makeSubject)
    }
}

final private class Connection<S: SubjectType>: ObserverType, Disposable {
    typealias E = S.SubjectObserverType.E

    private var _lock: RecursiveLock
    // state
    private var _parent: ConnectableObservableAdapter<S>?
    private var _subscription : Disposable?
    private var _subjectObserver: S.SubjectObserverType

    private let _disposed = AtomicInt(0)

    init(parent: ConnectableObservableAdapter<S>, subjectObserver: S.SubjectObserverType, lock: RecursiveLock, subscription: Disposable) {
        self._parent = parent
        self._subscription = subscription
        self._lock = lock
        self._subjectObserver = subjectObserver
    }

    func on(_ event: Event<S.SubjectObserverType.E>) {
        if isFlagSet(self._disposed, 1) {
            return
        }
        if event.isStopEvent {
            self.dispose()
        }
        self._subjectObserver.on(event)
    }

    func dispose() {
        _lock.lock(); defer { _lock.unlock() } // {
        fetchOr(self._disposed, 1)
        guard let parent = _parent else {
            return
        }

        if parent._connection === self {
            parent._connection = nil
            parent._subject = nil
        }
        self._parent = nil

        self._subscription?.dispose()
        self._subscription = nil
        // }
    }
}

final private class ConnectableObservableAdapter<S: SubjectType>
    : ConnectableObservable<S.E> {
    typealias ConnectionType = Connection<S>

    fileprivate let _source: Observable<S.SubjectObserverType.E>
    fileprivate let _makeSubject: () -> S

    fileprivate let _lock = RecursiveLock()
    fileprivate var _subject: S?

    // state
    fileprivate var _connection: ConnectionType?

    init(source: Observable<S.SubjectObserverType.E>, makeSubject: @escaping () -> S) {
        self._source = source
        self._makeSubject = makeSubject
        self._subject = nil
        self._connection = nil
    }

    override func connect() -> Disposable {
        return self._lock.calculateLocked {
            if let connection = self._connection {
                return connection
            }

            let singleAssignmentDisposable = SingleAssignmentDisposable()
            let connection = Connection(parent: self, subjectObserver: self.lazySubject.asObserver(), lock: self._lock, subscription: singleAssignmentDisposable)
            self._connection = connection
            let subscription = self._source.subscribe(connection)
            singleAssignmentDisposable.setDisposable(subscription)
            return connection
        }
    }

    fileprivate var lazySubject: S {
        if let subject = self._subject {
            return subject
        }

        let subject = self._makeSubject()
        self._subject = subject
        return subject
    }

    override func subscribe<O : ObserverType>(_ observer: O) -> Disposable where O.E == S.E {
        return self.lazySubject.subscribe(observer)
    }
}

final private class RefCountSink<CO: ConnectableObservableType, O: ObserverType>
    : Sink<O>
    , ObserverType where CO.E == O.E {
    typealias Element = O.E
    typealias Parent = RefCount<CO>

    private let _parent: Parent

    private var _connectionIdSnapshot: Int64 = -1

    init(parent: Parent, observer: O, cancel: Cancelable) {
        self._parent = parent
        super.init(observer: observer, cancel: cancel)
    }

    func run() -> Disposable {
        let subscription = self._parent._source.subscribe(self)
        self._parent._lock.lock(); defer { self._parent._lock.unlock() } // {

        self._connectionIdSnapshot = self._parent._connectionId

        if self.disposed {
            return Disposables.create()
        }

        if self._parent._count == 0 {
            self._parent._count = 1
            self._parent._connectableSubscription = self._parent._source.connect()
        }
        else {
            self._parent._count += 1
        }
        // }

        return Disposables.create {
            subscription.dispose()
            self._parent._lock.lock(); defer { self._parent._lock.unlock() } // {
            if self._parent._connectionId != self._connectionIdSnapshot {
                return
            }
            if self._parent._count == 1 {
                self._parent._count = 0
                guard let connectableSubscription = self._parent._connectableSubscription else {
                    return
                }

                connectableSubscription.dispose()
                self._parent._connectableSubscription = nil
            }
            else if self._parent._count > 1 {
                self._parent._count -= 1
            }
            else {
                rxFatalError("Something went wrong with RefCount disposing mechanism")
            }
            // }
        }
    }

    func on(_ event: Event<Element>) {
        switch event {
        case .next:
            self.forwardOn(event)
        case .error, .completed:
            self._parent._lock.lock() // {
                if self._parent._connectionId == self._connectionIdSnapshot {
                    let connection = self._parent._connectableSubscription
                    defer { connection?.dispose() }
                    self._parent._count = 0
                    self._parent._connectionId = self._parent._connectionId &+ 1
                    self._parent._connectableSubscription = nil
                }
            // }
            self._parent._lock.unlock()
            self.forwardOn(event)
            self.dispose()
        }
    }
}

final private class RefCount<CO: ConnectableObservableType>: Producer<CO.E> {
    fileprivate let _lock = RecursiveLock()

    // state
    fileprivate var _count = 0
    fileprivate var _connectionId: Int64 = 0
    fileprivate var _connectableSubscription = nil as Disposable?

    fileprivate let _source: CO

    init(source: CO) {
        self._source = source
    }

    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == CO.E {
        let sink = RefCountSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}

final private class MulticastSink<S: SubjectType, O: ObserverType>: Sink<O>, ObserverType {
    typealias Element = O.E
    typealias ResultType = Element
    typealias MutlicastType = Multicast<S, O.E>

    private let _parent: MutlicastType

    init(parent: MutlicastType, observer: O, cancel: Cancelable) {
        self._parent = parent
        super.init(observer: observer, cancel: cancel)
    }

    func run() -> Disposable {
        do {
            let subject = try self._parent._subjectSelector()
            let connectable = ConnectableObservableAdapter(source: self._parent._source, makeSubject: { subject })

            let observable = try self._parent._selector(connectable)

            let subscription = observable.subscribe(self)
            let connection = connectable.connect()

            return Disposables.create(subscription, connection)
        }
        catch let e {
            self.forwardOn(.error(e))
            self.dispose()
            return Disposables.create()
        }
    }

    func on(_ event: Event<ResultType>) {
        self.forwardOn(event)
        switch event {
        case .next: break
        case .error, .completed:
            self.dispose()
        }
    }
}

final private class Multicast<S: SubjectType, R>: Producer<R> {
    typealias SubjectSelectorType = () throws -> S
    typealias SelectorType = (Observable<S.E>) throws -> Observable<R>

    fileprivate let _source: Observable<S.SubjectObserverType.E>
    fileprivate let _subjectSelector: SubjectSelectorType
    fileprivate let _selector: SelectorType

    init(source: Observable<S.SubjectObserverType.E>, subjectSelector: @escaping SubjectSelectorType, selector: @escaping SelectorType) {
        self._source = source
        self._subjectSelector = subjectSelector
        self._selector = selector
    }

    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == R {
        let sink = MulticastSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}
