//
//  Signal+Subscription.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 9/19/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import RxSwift
import RxRelay

extension SharedSequenceConvertibleType where SharingStrategy == SignalSharingStrategy {
    /**
     Creates new subscription and sends elements to observer.

     In this form it's equivalent to `subscribe` method, but it communicates intent better.

     - parameter to: Observers that receives events.
     - returns: Disposable object that can be used to unsubscribe the observer from the subject.
     */
    public func emit<Observer: ObserverType>(to observers: Observer...) -> Disposable where Observer.Element == Element {
        return self.asSharedSequence()
                   .asObservable()
                   .subscribe { event in
                    observers.forEach { $0.on(event) }
                   }
    }

    /**
     Creates new subscription and sends elements to observer.

     In this form it's equivalent to `subscribe` method, but it communicates intent better.

     - parameter to: Observers that receives events.
     - returns: Disposable object that can be used to unsubscribe the observer from the subject.
     */
    public func emit<Observer: ObserverType>(to observers: Observer...) -> Disposable where Observer.Element == Element? {
        return self.asSharedSequence()
                   .asObservable()
                   .map { $0 as Element? }
                   .subscribe { event in
                       observers.forEach { $0.on(event) }
                   }
    }

    /**
     Creates new subscription and sends elements to `BehaviorRelay`.
     - parameter to: Target relays for sequence elements.
     - returns: Disposable object that can be used to unsubscribe the observer from the relay.
     */
    public func emit(to relays: BehaviorRelay<Element>...) -> Disposable {
        return self.emit(onNext: { e in
            relays.forEach { $0.accept(e) }
        })
    }
    
    /**
     Creates new subscription and sends elements to `BehaviorRelay`.
     - parameter to: Target relays for sequence elements.
     - returns: Disposable object that can be used to unsubscribe the observer from the relay.
     */
    public func emit(to relays: BehaviorRelay<Element?>...) -> Disposable {
        return self.emit(onNext: { e in
            relays.forEach { $0.accept(e) }
        })
    }
    
    /**
     Creates new subscription and sends elements to `PublishRelay`.

     - parameter to: Target relays for sequence elements.
     - returns: Disposable object that can be used to unsubscribe the observer from the relay.
     */
    public func emit(to relays: PublishRelay<Element>...) -> Disposable {
        return self.emit(onNext: { e in
            relays.forEach { $0.accept(e) }
        })
    }

    /**
     Creates new subscription and sends elements to `PublishRelay`.

     - parameter to: Target relay for sequence elements.
     - returns: Disposable object that can be used to unsubscribe the observer from the relay.
     */
    public func emit(to relays: PublishRelay<Element?>...) -> Disposable {
        return self.emit(onNext: { e in
            relays.forEach { $0.accept(e) }
        })
    }

    /**
     Creates new subscription and sends elements to `ReplayRelay`.

     - parameter to: Target relays for sequence elements.
     - returns: Disposable object that can be used to unsubscribe the observer from the relay.
     */
    public func emit(to relays: ReplayRelay<Element>...) -> Disposable {
        return self.emit(onNext: { e in
            relays.forEach { $0.accept(e) }
        })
    }

    /**
     Creates new subscription and sends elements to `ReplayRelay`.

     - parameter to: Target relay for sequence elements.
     - returns: Disposable object that can be used to unsubscribe the observer from the relay.
     */
    public func emit(to relays: ReplayRelay<Element?>...) -> Disposable {
        return self.emit(onNext: { e in
            relays.forEach { $0.accept(e) }
        })
    }
    
    /**
     Subscribes an element handler, a completion handler and disposed handler to an observable sequence.

     Also, take in an object and provide an unretained, safe to use (i.e. not implicitly unwrapped), reference to it along with the events emitted by the sequence.

     Error callback is not exposed because `Signal` can't error out.

     - Note: If `object` can't be retained, none of the other closures will be invoked.
     
     - parameter object: The object to provide an unretained reference on.
     - parameter onNext: Action to invoke for each element in the observable sequence.
     - parameter onCompleted: Action to invoke upon graceful termination of the observable sequence.
     gracefully completed, errored, or if the generation is canceled by disposing subscription)
     - parameter onDisposed: Action to invoke upon any type of termination of sequence (if the sequence has
     gracefully completed, errored, or if the generation is canceled by disposing subscription)
     - returns: Subscription object used to unsubscribe from the observable sequence.
     */
    public func emit<Object: AnyObject>(
        with object: Object,
        onNext: ((Object, Element) -> Void)? = nil,
        onCompleted: ((Object) -> Void)? = nil,
        onDisposed: ((Object) -> Void)? = nil
    ) -> Disposable {
        self.asObservable().subscribe(
            with: object,
            onNext: onNext,
            onCompleted: onCompleted,
            onDisposed: onDisposed
        )
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
    public func emit(
        onNext: ((Element) -> Void)? = nil,
        onCompleted: (() -> Void)? = nil,
        onDisposed: (() -> Void)? = nil
    ) -> Disposable {
        self.asObservable().subscribe(onNext: onNext, onCompleted: onCompleted, onDisposed: onDisposed)
    }

    /**
    Subscribes to this `Signal` with a no-op.
    This method can be only called from `MainThread`.

    - note: This is an alias of `emit(onNext: nil, onCompleted: nil, onDisposed: nil)` used to fix an ambiguity bug in Swift: https://bugs.swift.org/browse/SR-13657

    - returns: Subscription object used to unsubscribe from the observable sequence.
    */
    public func emit() -> Disposable {
        emit(onNext: nil, onCompleted: nil, onDisposed: nil)
    }
}
