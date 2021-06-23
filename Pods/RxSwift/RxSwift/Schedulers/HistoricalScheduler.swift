//
//  HistoricalScheduler.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 12/27/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

/// Provides a virtual time scheduler that uses `Date` for absolute time and `NSTimeInterval` for relative time.
public class HistoricalScheduler : VirtualTimeScheduler<HistoricalSchedulerTimeConverter> {

    /**
      Creates a new historical scheduler with initial clock value.
     
     - parameter initialClock: Initial value for virtual clock.
    */
    public init(initialClock: RxTime = Date(timeIntervalSince1970: 0)) {
        super.init(initialClock: initialClock, converter: HistoricalSchedulerTimeConverter())
    }
}
