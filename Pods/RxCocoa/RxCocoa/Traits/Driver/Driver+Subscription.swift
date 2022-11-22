//
//  Driver+Subscription.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 9/19/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import RxSwift
import RxRelay

private let errorMessage = "`drive*` family of methods can be only called from `MainThread`.\n" +
"This is required to ensure that the last replayed `Driver` element is delivered on `MainThread`.\n"

extension SharedSequenceConvertibleType where SharingStrategy == DriverSharingStrategy {
    /**
    Creates new subscription and sends elements to observer.
    This method can be only called from `MainThread`.

    In this form it's equivalent to `subscribe` method, but it communicates intent better.

    - parameter observers: Observers that receives events.
    - returns: Disposable object that can be used to unsubscribe the observer from the subject.
    */
    public func drive<Observer: ObserverType>(_ observers: Observer...) -> Disposable where Observer.Element == Element {
        MainScheduler.ensureRunningOnMainThread(errorMessage: errorMessage)
        return self.asSharedSequence()
                   .asObservable()
                   .subscribe { e in
                    observers.forEach { $0.on(e) }
                   }
    }

    /**
     Creates new subscription and sends elements to observer.
     This method can be only called from `MainThread`.

     In this form it's equivalent to `subscribe` method, but it communicates intent better.

     - parameter observers: Observers that receives events.
     - returns: Disposable object that can be used to unsubscribe the observer from the subject.
     */
    public func drive<Observer: ObserverType>(_ observers: Observer...) -> Disposable where Observer.Element == Element? {
        MainScheduler.ensureRunningOnMainThread(errorMessage: errorMessage)
        return self.asSharedSequence()
                   .asObservable()
                   .map { $0 as Element? }
                   .subscribe { e in
                    observers.forEach { $0.on(e) }
                   }
    }

    /**
    Creates new subscription and sends elements to `BehaviorRelay`.
    This method can be only called from `MainThread`.

    - parameter relays: Target relays for sequence elements.
    - returns: Disposable object that can be used to unsubscribe the observer from the relay.
    */
    public func drive(_ relays: BehaviorRelay<Element>...) -> Disposable {
        MainScheduler.ensureRunningOnMainThread(errorMessage: errorMessage)
        return self.drive(onNext: { e in
            relays.forEach { $0.accept(e) }
        })
    }

    /**
     Creates new subscription and sends elements to `BehaviorRelay`.
     This method can be only called from `MainThread`.

     - parameter relays: Target relays for sequence elements.
     - returns: Disposable object that can be used to unsubscribe the observer from the relay.
     */
    public func drive(_ relays: BehaviorRelay<Element?>...) -> Disposable {
        MainScheduler.ensureRunningOnMainThread(errorMessage: errorMessage)
        return self.drive(onNext: { e in
            relays.forEach { $0.accept(e) }
        })
    }

    /**
    Creates new subscription and sends elements to `ReplayRelay`.
    This method can be only called from `MainThread`.

    - parameter relays: Target relays for sequence elements.
    - returns: Disposable object that can be used to unsubscribe the observer from the relay.
    */
    public func drive(_ relays: ReplayRelay<Element>...) -> Disposable {
        MainScheduler.ensureRunningOnMainThread(errorMessage: errorMessage)
        return self.drive(onNext: { e in
            relays.forEach { $0.accept(e) }
        })
    }

    /**
     Creates new subscription and sends elements to `ReplayRelay`.
     This method can be only called from `MainThread`.

     - parameter relays: Target relays for sequence elements.
     - returns: Disposable object that can be used to unsubscribe the observer from the relay.
     */
    public func drive(_ relays: ReplayRelay<Element?>...) -> Disposable {
        MainScheduler.ensureRunningOnMainThread(errorMessage: errorMessage)
        return self.drive(onNext: { e in
            relays.forEach { $0.accept(e) }
        })
    }

    /**
    Subscribes to observable sequence using custom binder function.
    This method can be only called from `MainThread`.

    - parameter transformation: Function used to bind elements from `self`.
    - returns: Object representing subscription.
    */
    public func drive<Result>(_ transformation: (Observable<Element>) -> Result) -> Result {
        MainScheduler.ensureRunningOnMainThread(errorMessage: errorMessage)
        return transformation(self.asObservable())
    }

    /**
    Subscribes to observable sequence using custom binder function and final parameter passed to binder function
    after `self` is passed.

        public func drive<R1, R2>(with: Self -> R1 -> R2, curriedArgument: R1) -> R2 {
            return with(self)(curriedArgument)
        }

    This method can be only called from `MainThread`.

    - parameter with: Function used to bind elements from `self`.
    - parameter curriedArgument: Final argument passed to `binder` to finish binding process.
    - returns: Object representing subscription.
    */
    public func drive<R1, R2>(_ with: (Observable<Element>) -> (R1) -> R2, curriedArgument: R1) -> R2 {
        MainScheduler.ensureRunningOnMainThread(errorMessage: errorMessage)
        return with(self.asObservable())(curriedArgument)
    }
    
    /**
    Subscribes an element handler, a completion handler and disposed handler to an observable sequence.
    This method can be only called from `MainThread`.
     
    Also, take in an object and provide an unretained, safe to use (i.e. not implicitly unwrapped), reference to it along with the events emitted by the sequence.
    
    Error callback is not exposed because `Driver` can't error out.
     
     - Note: If `object` can't be retained, none of the other closures will be invoked.
     
    - parameter object: The object to provide an unretained reference on.
    - parameter onNext: Action to invoke for each element in the observable sequence.
    - parameter onCompleted: Action to invoke upon graceful termination of the observable sequence.
    gracefully completed, errored, or if the generation is canceled by disposing subscription)
    - parameter onDisposed: Action to invoke upon any type of termination of sequence (if the sequence has
    gracefully completed, errored, or if the generation is canceled by disposing subscription)
    - returns: Subscription object used to unsubscribe from the observable sequence.
    */
    public func drive<Object: AnyObject>(
        with object: Object,
        onNext: ((Object, Element) -> Void)? = nil,
        onCompleted: ((Object) -> Void)? = nil,
        onDisposed: ((Object) -> Void)? = nil
    ) -> Disposable {
        MainScheduler.ensureRunningOnMainThread(errorMessage: errorMessage)
        return self.asObservable().subscribe(with: object, onNext: onNext, onCompleted: onCompleted, onDisposed: onDisposed)
    }
    
    /**
    Subscribes an element handler, a completion handler and disposed handler to an observable sequence.
    This method can be only called from `MainThread`.
    
    Error callback is not exposed because `Driver` can't error out.
    
    - parameter onNext: Action to invoke for each element in the observable sequence.
    - parameter onCompleted: Action to invoke upon graceful termination of the observable sequence.
    gracefully completed, errored, or if the generation is canceled by disposing subscription)
    - parameter onDisposed: Action to invoke upon any type of termination of sequence (if the sequence has
    gracefully completed, errored, or if the generation is canceled by disposing subscription)
    - returns: Subscription object used to unsubscribe from the observable sequence.
    */
    public func drive(
        onNext: ((Element) -> Void)? = nil,
        onCompleted: (() -> Void)? = nil,
        onDisposed: (() -> Void)? = nil
    ) -> Disposable {
        MainScheduler.ensureRunningOnMainThread(errorMessage: errorMessage)
        return self.asObservable().subscribe(onNext: onNext, onCompleted: onCompleted, onDisposed: onDisposed)
    }

    /**
    Subscribes to this `Driver` with a no-op.
    This method can be only called from `MainThread`.

    - note: This is an alias of `drive(onNext: nil, onCompleted: nil, onDisposed: nil)` used to fix an ambiguity bug in Swift: https://bugs.swift.org/browse/SR-13657

    - returns: Subscription object used to unsubscribe from the observable sequence.
    */
    public func drive() -> Disposable {
        drive(onNext: nil, onCompleted: nil, onDisposed: nil)
    }
}


