//
//  Driver.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 9/26/16.
//  Copyright © 2016 Krunoslav Zaher. All rights reserved.
//

import Foundation
#if !RX_NO_MODULE
    import RxSwift
#endif


/**
 Unit that represents observable sequence with following properties:

 - it never fails
 - it delivers events on `MainScheduler.instance`
 - `shareReplayLatestWhileConnected()` behavior
 - all observers share sequence computation resources
 - it's stateful, upon subscription (calling subscribe) last element is immediatelly replayed if it was produced
 - computation of elements is reference counted with respect to the number of observers
 - if there are no subscribers, it will release sequence computation resources

 `Driver<Element>` can be considered a builder pattern for observable sequences that drive the application.

 If observable sequence has produced at least one element, after new subscription is made last produced element will be
 immediately replayed on the same thread on which the subscription was made.

 When using `drive*`, `subscribe*` and `bind*` family of methods, they should always be called from main thread.

 If `drive*`, `subscribe*` and `bind*` are called from background thread, it is possible that initial replay
 will happen on background thread, and subsequent events will arrive on main thread.

 To find out more about units and how to use them, please visit `Documentation/Units.md`.
 */
public typealias Driver<E> = SharedSequence<DriverSharingStrategy, E>

public struct DriverSharingStrategy: SharingStrategyProtocol {
    public static var scheduler: SchedulerType { return driverObserveOnScheduler }
    public static func share<E>(_ source: Observable<E>) -> Observable<E> {
        return source.shareReplayLatestWhileConnected()
    }
}

extension SharedSequenceConvertibleType where SharingStrategy == DriverSharingStrategy {
    /// Adds `asDriver` to `SharingSequence` with `DriverSharingStrategy`.
    public func asDriver() -> Driver<E> {
        return self.asSharedSequence()
    }
}

/**
 This method can be used in unit tests to ensure that driver is using mock schedulers instead of
 main schedulers.

 **This shouldn't be used in normal release builds.**
*/
public func driveOnScheduler(_ scheduler: SchedulerType, action: () -> ()) {
    let originalObserveOnScheduler = driverObserveOnScheduler
    driverObserveOnScheduler = scheduler

    action()

    // If you remove this line , compiler buggy optimizations will change behavior of this code
    _forceCompilerToStopDoingInsaneOptimizationsThatBreakCode(driverObserveOnScheduler)
    // Scary, I know

    driverObserveOnScheduler = originalObserveOnScheduler
}

#if os(Linux)
    import Glibc
#endif

func _forceCompilerToStopDoingInsaneOptimizationsThatBreakCode(_ scheduler: SchedulerType) {
    let a: Int32 = 1
#if os(Linux)
    let b = 314 + Int32(Glibc.random() & 1)
#else
    let b = 314 + Int32(arc4random() & 1)
#endif
    if a == b {
        print(scheduler)
    }
}

fileprivate var driverObserveOnScheduler: SchedulerType = MainScheduler.instance
