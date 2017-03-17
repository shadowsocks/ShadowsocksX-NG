//
//  VirtualTimeConverterType.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 12/23/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

/// Parametrization for virtual time used by `VirtualTimeScheduler`s.
public protocol VirtualTimeConverterType {
    /// Virtual time unit used that represents ticks of virtual clock.
    associatedtype VirtualTimeUnit

    /// Virtual time unit used to represent differences of virtual times.
    associatedtype VirtualTimeIntervalUnit

    /**
     Converts virtual time to real time.
     
     - parameter virtualTime: Virtual time to convert to `Date`.
     - returns: `Date` corresponding to virtual time.
    */
    func convertFromVirtualTime(_ virtualTime: VirtualTimeUnit) -> RxTime

    /**
     Converts real time to virtual time.
     
     - parameter time: `Date` to convert to virtual time.
     - returns: Virtual time corresponding to `Date`.
    */
    func convertToVirtualTime(_ time: RxTime) -> VirtualTimeUnit

    /**
     Converts from virtual time interval to `NSTimeInterval`.
     
     - parameter virtualTimeInterval: Virtual time interval to convert to `NSTimeInterval`.
     - returns: `NSTimeInterval` corresponding to virtual time interval.
    */
    func convertFromVirtualTimeInterval(_ virtualTimeInterval: VirtualTimeIntervalUnit) -> RxTimeInterval

    /**
     Converts from virtual time interval to `NSTimeInterval`.
     
     - parameter timeInterval: `NSTimeInterval` to convert to virtual time interval.
     - returns: Virtual time interval corresponding to time interval.
    */
    func convertToVirtualTimeInterval(_ timeInterval: RxTimeInterval) -> VirtualTimeIntervalUnit

    /**
     Offsets virtual time by virtual time interval.
     
     - parameter time: Virtual time.
     - parameter offset: Virtual time interval.
     - returns: Time corresponding to time offsetted by virtual time interval.
    */
    func offsetVirtualTime(_ time: VirtualTimeUnit, offset: VirtualTimeIntervalUnit) -> VirtualTimeUnit

    /**
     This is aditional abstraction because `Date` is unfortunately not comparable.
     Extending `Date` with `Comparable` would be too risky because of possible collisions with other libraries.
    */
    func compareVirtualTime(_ lhs: VirtualTimeUnit, _ rhs: VirtualTimeUnit) -> VirtualTimeComparison
}

/**
 Virtual time comparison result.

 This is aditional abstraction because `Date` is unfortunately not comparable.
 Extending `Date` with `Comparable` would be too risky because of possible collisions with other libraries.
*/
public enum VirtualTimeComparison {
    /// lhs < rhs.
    case lessThan
    /// lhs == rhs.
    case equal
    /// lhs > rhs.
    case greaterThan
}

extension VirtualTimeComparison {
    /// lhs < rhs.
    var lessThen: Bool {
        return self == .lessThan
    }

    /// lhs > rhs
    var greaterThan: Bool {
        return self == .greaterThan
    }

    /// lhs == rhs
    var equal: Bool {
        return self == .equal
    }
}
