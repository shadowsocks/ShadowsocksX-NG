//
//  ConnectableObservable.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/1/15.
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

final class Connection<S: SubjectType> : ObserverType, Disposable {
    typealias E = S.SubjectObserverType.E

    private var _lock: RecursiveLock
    // state
    private var _parent: ConnectableObservableAdapter<S>?
    private var _subscription : Disposable?
    private var _subjectObserver: S.SubjectObserverType

    private var _disposed: Bool = false

    init(parent: ConnectableObservableAdapter<S>, subjectObserver: S.SubjectObserverType, lock: RecursiveLock, subscription: Disposable) {
        _parent = parent
        _subscription = subscription
        _lock = lock
        _subjectObserver = subjectObserver
    }

    func on(_ event: Event<S.SubjectObserverType.E>) {
        if _disposed {
            return
        }
        _subjectObserver.on(event)
        if event.isStopEvent {
            self.dispose()
        }
    }
    
    func dispose() {
        _lock.lock(); defer { _lock.unlock() } // {
            _disposed = true
            guard let parent = _parent else {
                return
            }
        
            if parent._connection === self {
                parent._connection = nil
            }
            _parent = nil

            _subscription?.dispose()
            _subscription = nil
        // }
    }
}

final class ConnectableObservableAdapter<S: SubjectType>
    : ConnectableObservable<S.E> {
    typealias ConnectionType = Connection<S>
    
    fileprivate let _subject: S
    fileprivate let _source: Observable<S.SubjectObserverType.E>
    
    fileprivate let _lock = RecursiveLock()
    
    // state
    fileprivate var _connection: ConnectionType?
    
    init(source: Observable<S.SubjectObserverType.E>, subject: S) {
        _source = source
        _subject = subject
        _connection = nil
    }
    
    override func connect() -> Disposable {
        return _lock.calculateLocked {
            if let connection = _connection {
                return connection
            }

            let singleAssignmentDisposable = SingleAssignmentDisposable()
            let connection = Connection(parent: self, subjectObserver: _subject.asObserver(), lock: _lock, subscription: singleAssignmentDisposable)
            _connection = connection
            let subscription = _source.subscribe(connection)
            singleAssignmentDisposable.setDisposable(subscription)
            return connection
        }
    }
    
    override func subscribe<O : ObserverType>(_ observer: O) -> Disposable where O.E == S.E {
        return _subject.subscribe(observer)
    }
}
