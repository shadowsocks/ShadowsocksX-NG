//
//  Observable+Binding.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/1/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

// MARK: multicast

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
        return ConnectableObservableAdapter(source: self.asObservable(), subject: subject)
    }

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

// MARK: publish

extension ObservableType {
    
    /**
    Returns a connectable observable sequence that shares a single subscription to the underlying sequence. 
    
    This operator is a specialization of `multicast` using a `PublishSubject`.

    - seealso: [publish operator on reactivex.io](http://reactivex.io/documentation/operators/publish.html)
    
    - returns: A connectable observable sequence that shares a single subscription to the underlying sequence.
    */
    public func publish() -> ConnectableObservable<E> {
        return self.multicast(PublishSubject())
    }
}

// MARK: replay

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
        return self.multicast(ReplaySubject.create(bufferSize: bufferSize))
    }

    /**
    Returns a connectable observable sequence that shares a single subscription to the underlying sequence replaying all elements.

    This operator is a specialization of `multicast` using a `ReplaySubject`.

    - seealso: [replay operator on reactivex.io](http://reactivex.io/documentation/operators/replay.html)

    - returns: A connectable observable sequence that shares a single subscription to the underlying sequence.
    */
    public func replayAll()
        -> ConnectableObservable<E> {
        return self.multicast(ReplaySubject.createUnbounded())
    }
}

// MARK: refcount

extension ConnectableObservableType {
    
    /**
    Returns an observable sequence that stays connected to the source as long as there is at least one subscription to the observable sequence.

    - seealso: [refCount operator on reactivex.io](http://reactivex.io/documentation/operators/refCount.html)
    
    - returns: An observable sequence that stays connected to the source as long as there is at least one subscription to the observable sequence.
    */
    public func refCount() -> Observable<E> {
        return RefCount(source: self)
    }
}

// MARK: share

extension ObservableType {
    
    /**
    Returns an observable sequence that shares a single subscription to the underlying sequence.
    
    This operator is a specialization of publish which creates a subscription when the number of observers goes from zero to one, then shares that subscription with all subsequent observers until the number of observers returns to zero, at which point the subscription is disposed.

    - seealso: [share operator on reactivex.io](http://reactivex.io/documentation/operators/refcount.html)

    - returns: An observable sequence that contains the elements of a sequence produced by multicasting the source sequence.
    */
    public func share() -> Observable<E> {
        return self.publish().refCount()
    }
}

// MARK: shareReplay

extension ObservableType {
    
    /**
    Returns an observable sequence that shares a single subscription to the underlying sequence, and immediately upon subscription replays maximum number of elements in buffer.
    
    This operator is a specialization of replay which creates a subscription when the number of observers goes from zero to one, then shares that subscription with all subsequent observers until the number of observers returns to zero, at which point the subscription is disposed.

    - seealso: [shareReplay operator on reactivex.io](http://reactivex.io/documentation/operators/replay.html)
    
    - parameter bufferSize: Maximum element count of the replay buffer.
    - returns: An observable sequence that contains the elements of a sequence produced by multicasting the source sequence.
    */
    public func shareReplay(_ bufferSize: Int)
        -> Observable<E> {
        if bufferSize == 1 {
            return ShareReplay1(source: self.asObservable())
        }
        else {
            return self.replay(bufferSize).refCount()
        }
    }

    /**
    Returns an observable sequence that shares a single subscription to the underlying sequence, and immediately upon subscription replays latest element in buffer.

    This operator is a specialization of replay which creates a subscription when the number of observers goes from zero to one, then shares that subscription with all subsequent observers until the number of observers returns to zero, at which point the subscription is disposed.
     
    Unlike `shareReplay(bufferSize: Int)`, this operator will clear latest element from replay buffer in case number of subscribers drops from one to zero. In case sequence
    completes or errors out replay buffer is also cleared.

    - seealso: [shareReplay operator on reactivex.io](http://reactivex.io/documentation/operators/replay.html)
    
    - returns: An observable sequence that contains the elements of a sequence produced by multicasting the source sequence.
    */
    public func shareReplayLatestWhileConnected()
        -> Observable<E> {
        return ShareReplay1WhileConnected(source: self.asObservable())
    }
}
