//
//  SchedulerType+SharedSequence.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 8/27/17.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

import RxSwift

public enum SharingScheduler {
    /// Default scheduler used in SharedSequence based traits.
    public private(set) static var make: () -> SchedulerType = { MainScheduler() }

    /**
     This method can be used in unit tests to ensure that built in shared sequences are using mock schedulers instead
     of main schedulers.

     **This shouldn't be used in normal release builds.**
    */
    static public func mock(scheduler: SchedulerType, action: () -> ()) {
        return mock(makeScheduler: { scheduler }, action: action)
    }

    /**
     This method can be used in unit tests to ensure that built in shared sequences are using mock schedulers instead
     of main schedulers.

     **This shouldn't be used in normal release builds.**
     */
    static public func mock(makeScheduler: @escaping () -> SchedulerType, action: () -> ()) {
        let originalMake = make
        make = makeScheduler

        action()

        // If you remove this line , compiler buggy optimizations will change behavior of this code
        _forceCompilerToStopDoingInsaneOptimizationsThatBreakCode(makeScheduler)
        // Scary, I know

        make = originalMake
    }
}

#if os(Linux)
    import Glibc
#else
    import func Foundation.arc4random
#endif

func _forceCompilerToStopDoingInsaneOptimizationsThatBreakCode(_ scheduler: () -> SchedulerType) {
    let a: Int32 = 1
#if os(Linux)
    let b = 314 + Int32(Glibc.random() & 1)
#else
    let b = 314 + Int32(arc4random() & 1)
#endif
    if a == b {
        print(scheduler())
    }
}
