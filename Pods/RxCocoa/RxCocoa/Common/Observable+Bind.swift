//
//  Observable+Bind.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 8/29/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import RxSwift

extension ObservableType {
    /**
     Creates new subscription and sends elements to observer(s).
     In this form, it's equivalent to the `subscribe` method, but it better conveys intent, and enables
     writing more consistent binding code.
     - parameter to: Observers to receives events.
     - returns: Disposable object that can be used to unsubscribe the observers.
     */
    public func bind<Observer: ObserverType>(to observers: Observer...) -> Disposable where Observer.Element == Element {
        self.subscribe { event in
            observers.forEach { $0.on(event) }
        }
    }

    /**
     Creates new subscription and sends elements to observer(s).
     In this form, it's equivalent to the `subscribe` method, but it better conveys intent, and enables
     writing more consistent binding code.
     - parameter to: Observers to receives events.
     - returns: Disposable object that can be used to unsubscribe the observers.
     */
    public func bind<Observer: ObserverType>(to observers: Observer...) -> Disposable where Observer.Element == Element? {
        self.map { $0 as Element? }
            .subscribe { event in
                observers.forEach { $0.on(event) }
            }
    }

    /**
    Subscribes to observable sequence using custom binder function.

    - parameter to: Function used to bind elements from `self`.
    - returns: Object representing subscription.
    */
    public func bind<Result>(to binder: (Self) -> Result) -> Result {
        binder(self)
    }

    /**
    Subscribes to observable sequence using custom binder function and final parameter passed to binder function
    after `self` is passed.

        public func bind<R1, R2>(to binder: Self -> R1 -> R2, curriedArgument: R1) -> R2 {
            return binder(self)(curriedArgument)
        }

    - parameter to: Function used to bind elements from `self`.
    - parameter curriedArgument: Final argument passed to `binder` to finish binding process.
    - returns: Object representing subscription.
    */
    public func bind<R1, R2>(to binder: (Self) -> (R1) -> R2, curriedArgument: R1) -> R2 {
        binder(self)(curriedArgument)
    }
    
    /**
    Subscribes an element handler to an observable sequence.
    In case error occurs in debug mode, `fatalError` will be raised.
    In case error occurs in release mode, `error` will be logged.

     - Note: If `object` can't be retained, none of the other closures will be invoked.
     
    - parameter object: The object to provide an unretained reference on.
    - parameter onNext: Action to invoke for each element in the observable sequence.
    - returns: Subscription object used to unsubscribe from the observable sequence.
    */
    public func bind<Object: AnyObject>(
        with object: Object,
        onNext: @escaping (Object, Element) -> Void
    ) -> Disposable {
        self.subscribe(onNext: { [weak object] in
            guard let object = object else { return }
            onNext(object, $0)
        },
        onError: { error in
            rxFatalErrorInDebug("Binding error: \(error)")
        })
    }
    
    /**
    Subscribes an element handler to an observable sequence.
    In case error occurs in debug mode, `fatalError` will be raised.
    In case error occurs in release mode, `error` will be logged.

    - parameter onNext: Action to invoke for each element in the observable sequence.
    - returns: Subscription object used to unsubscribe from the observable sequence.
    */
    public func bind(onNext: @escaping (Element) -> Void) -> Disposable {
        self.subscribe(onNext: onNext,
                       onError: { error in
                        rxFatalErrorInDebug("Binding error: \(error)")
                       })
    }
}
