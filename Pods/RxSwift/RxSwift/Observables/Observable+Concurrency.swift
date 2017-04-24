//
//  Observable+Concurrency.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/15/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

// MARK: observeOn

extension ObservableType {
    
    /**
    Wraps the source sequence in order to run its observer callbacks on the specified scheduler.
    
    This only invokes observer callbacks on a `scheduler`. In case the subscription and/or unsubscription
    actions have side-effects that require to be run on a scheduler, use `subscribeOn`.

    - seealso: [observeOn operator on reactivex.io](http://reactivex.io/documentation/operators/observeon.html)
    
    - parameter scheduler: Scheduler to notify observers on.
    - returns: The source sequence whose observations happen on the specified scheduler.
    */
    public func observeOn(_ scheduler: ImmediateSchedulerType)
        -> Observable<E> {
        if let scheduler = scheduler as? SerialDispatchQueueScheduler {
            return ObserveOnSerialDispatchQueue(source: self.asObservable(), scheduler: scheduler)
        }
        else {
            return ObserveOn(source: self.asObservable(), scheduler: scheduler)
        }
    }
}

// MARK: subscribeOn

extension ObservableType {
    
    /**
    Wraps the source sequence in order to run its subscription and unsubscription logic on the specified 
    scheduler. 
    
    This operation is not commonly used.
    
    This only performs the side-effects of subscription and unsubscription on the specified scheduler. 
    
    In order to invoke observer callbacks on a `scheduler`, use `observeOn`.

    - seealso: [subscribeOn operator on reactivex.io](http://reactivex.io/documentation/operators/subscribeon.html)
    
    - parameter scheduler: Scheduler to perform subscription and unsubscription actions on.
    - returns: The source sequence whose subscriptions and unsubscriptions happen on the specified scheduler.
    */
    public func subscribeOn(_ scheduler: ImmediateSchedulerType)
        -> Observable<E> {
        return SubscribeOn(source: self, scheduler: scheduler)
    }
}
