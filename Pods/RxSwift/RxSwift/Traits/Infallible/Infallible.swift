//
//  Infallible.swift
//  RxSwift
//
//  Created by Shai Mishali on 27/08/2020.
//  Copyright © 2020 Krunoslav Zaher. All rights reserved.
//

/// `Infallible` is an `Observable`-like push-style interface
/// which is guaranteed to not emit error events.
///
/// Unlike `SharedSequence`, it does not share its resources or
/// replay its events, but acts as a standard `Observable`.
public protocol InfallibleType: ObservableConvertibleType {}

/// `Infallible` is an `Observable`-like push-style interface
/// which is guaranteed to not emit error events.
///
/// Unlike `SharedSequence`, it does not share its resources or
/// replay its events, but acts as a standard `Observable`.
public struct Infallible<Element>: InfallibleType {
    private let source: Observable<Element>

    init(_ source: Observable<Element>) {
        self.source = source
    }

    public func asObservable() -> Observable<Element> { source }
}

extension InfallibleType {
    /**
     Subscribes an element handler, a completion handler and disposed handler to an observable sequence.
     
     Error callback is not exposed because `Infallible` can't error out.
     
     Also, take in an object and provide an unretained, safe to use (i.e. not implicitly unwrapped), reference to it along with the events emitted by the sequence.
     
     - Note: If `object` can't be retained, none of the other closures will be invoked.
     
     - parameter object: The object to provide an unretained reference on.
     - parameter onNext: Action to invoke for each element in the observable sequence.
     - parameter onCompleted: Action to invoke upon graceful termination of the observable sequence.
     gracefully completed, errored, or if the generation is canceled by disposing subscription)
     - parameter onDisposed: Action to invoke upon any type of termination of sequence (if the sequence has
     gracefully completed, errored, or if the generation is canceled by disposing subscription)
     - returns: Subscription object used to unsubscribe from the observable sequence.
     */
    public func subscribe<Object: AnyObject>(
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
     
     Error callback is not exposed because `Infallible` can't error out.
     
     - parameter onNext: Action to invoke for each element in the observable sequence.
     - parameter onCompleted: Action to invoke upon graceful termination of the observable sequence.
     gracefully completed, errored, or if the generation is canceled by disposing subscription)
     - parameter onDisposed: Action to invoke upon any type of termination of sequence (if the sequence has
     gracefully completed, errored, or if the generation is canceled by disposing subscription)
     - returns: Subscription object used to unsubscribe from the observable sequence.
    */
    public func subscribe(onNext: ((Element) -> Void)? = nil,
                          onCompleted: (() -> Void)? = nil,
                          onDisposed: (() -> Void)? = nil) -> Disposable {
        self.asObservable().subscribe(onNext: onNext,
                                      onCompleted: onCompleted,
                                      onDisposed: onDisposed)
    }

    /**
     Subscribes an event handler to an observable sequence.
     
     - parameter on: Action to invoke for each event in the observable sequence.
     - returns: Subscription object used to unsubscribe from the observable sequence.
     */
    public func subscribe(_ on: @escaping (Event<Element>) -> Void) -> Disposable {
        self.asObservable().subscribe(on)
    }
}
