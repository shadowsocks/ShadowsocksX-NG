//
//  Signal+Subscription.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 9/19/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import RxSwift

extension SharedSequenceConvertibleType where SharingStrategy == SignalSharingStrategy {
    /**
     Creates new subscription and sends elements to observer.

     In this form it's equivalent to `subscribe` method, but it communicates intent better.

     - parameter to: Observer that receives events.
     - returns: Disposable object that can be used to unsubscribe the observer from the subject.
     */
    public func emit<O: ObserverType>(to observer: O) -> Disposable where O.E == E {
        return self.asSharedSequence().asObservable().subscribe(observer)
    }

    /**
     Creates new subscription and sends elements to observer.

     In this form it's equivalent to `subscribe` method, but it communicates intent better.

     - parameter to: Observer that receives events.
     - returns: Disposable object that can be used to unsubscribe the observer from the subject.
     */
    public func emit<O: ObserverType>(to observer: O) -> Disposable where O.E == E? {
        return self.asSharedSequence().asObservable().map { $0 as E? }.subscribe(observer)
    }

    /**
     Creates new subscription and sends elements to variable.

     - parameter relay: Target relay for sequence elements.
     - returns: Disposable object that can be used to unsubscribe the observer from the variable.
     */
    public func emit(to relay: PublishRelay<E>) -> Disposable {
        return emit(onNext: { e in
            relay.accept(e)
        })
    }

    /**
     Creates new subscription and sends elements to variable.

     - parameter to: Target relay for sequence elements.
     - returns: Disposable object that can be used to unsubscribe the observer from the variable.
     */
    public func emit(to relay: PublishRelay<E?>) -> Disposable {
        return emit(onNext: { e in
            relay.accept(e)
        })
    }

    /**
     Subscribes an element handler, a completion handler and disposed handler to an observable sequence.

     Error callback is not exposed because `Signal` can't error out.

     - parameter onNext: Action to invoke for each element in the observable sequence.
     - parameter onCompleted: Action to invoke upon graceful termination of the observable sequence.
     gracefully completed, errored, or if the generation is canceled by disposing subscription)
     - parameter onDisposed: Action to invoke upon any type of termination of sequence (if the sequence has
     gracefully completed, errored, or if the generation is canceled by disposing subscription)
     - returns: Subscription object used to unsubscribe from the observable sequence.
     */
    public func emit(onNext: ((E) -> Void)? = nil, onCompleted: (() -> Void)? = nil, onDisposed: (() -> Void)? = nil) -> Disposable {
        return self.asObservable().subscribe(onNext: onNext, onCompleted: onCompleted, onDisposed: onDisposed)
    }
}



