//
//  Signal.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 9/26/16.
//  Copyright © 2016 Krunoslav Zaher. All rights reserved.
//

import RxSwift

/**
 Trait that represents observable sequence with following properties:
 
 - it never fails
 - it delivers events on `MainScheduler.instance`
 - `share(scope: .whileConnected)` sharing strategy

 Additional explanation:
 - all observers share sequence computation resources
 - there is no replaying of sequence elements on new observer subscription
 - computation of elements is reference counted with respect to the number of observers
 - if there are no subscribers, it will release sequence computation resources

 In case trait that models state propagation is required, please check `Driver`.

 `Signal<Element>` can be considered a builder pattern for observable sequences that model imperative events part of the application.
 
 To find out more about units and how to use them, please visit `Documentation/Traits.md`.
 */
public typealias Signal<E> = SharedSequence<SignalSharingStrategy, E>

public struct SignalSharingStrategy : SharingStrategyProtocol {
    public static var scheduler: SchedulerType { return SharingScheduler.make() }
    
    public static func share<E>(_ source: Observable<E>) -> Observable<E> {
        return source.share(scope: .whileConnected)
    }
}

extension SharedSequenceConvertibleType where SharingStrategy == SignalSharingStrategy {
    /// Adds `asPublisher` to `SharingSequence` with `PublishSharingStrategy`.
    public func asSignal() -> Signal<E> {
        return asSharedSequence()
    }
}
