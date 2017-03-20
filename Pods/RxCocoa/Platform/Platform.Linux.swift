//
//  Platform.Linux.swift
//  Platform
//
//  Created by Krunoslav Zaher on 12/29/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if os(Linux)

    import XCTest
    import Glibc
    import SwiftShims
    import class Foundation.Thread

    final class AtomicInt {
        typealias IntegerLiteralType = Int
        fileprivate var value: Int32 = 0
        fileprivate var _lock = RecursiveLock()

        func lock() {
          _lock.lock()
        }
        func unlock() {
          _lock.unlock()
        }

        func valueSnapshot() -> Int32 {
            return value
        }
    }

    extension AtomicInt: ExpressibleByIntegerLiteral {
        convenience init(integerLiteral value: Int) {
            self.init()
            self.value = Int32(value)
        }
    }
    
    func >(lhs: AtomicInt, rhs: Int32) -> Bool {
        return lhs.value > rhs
    }
    func ==(lhs: AtomicInt, rhs: Int32) -> Bool {
        return lhs.value == rhs
    }

    func AtomicFlagSet(_ mask: UInt32, _ atomic: inout AtomicInt) -> Bool {
        atomic.lock(); defer { atomic.unlock() }
        return (atomic.value & Int32(mask)) != 0
    }

    func AtomicOr(_ mask: UInt32, _ atomic: inout AtomicInt) -> Int32 {
        atomic.lock(); defer { atomic.unlock() }
        let value = atomic.value
        atomic.value |= Int32(mask)
        return value
    }

    func AtomicIncrement(_ atomic: inout AtomicInt) -> Int32 {
        atomic.lock(); defer { atomic.unlock() }
        atomic.value += 1
        return atomic.value
    }

    func AtomicDecrement(_ atomic: inout AtomicInt) -> Int32 {
        atomic.lock(); defer { atomic.unlock() }
        atomic.value -= 1
        return atomic.value
    }

    func AtomicCompareAndSwap(_ l: Int32, _ r: Int32, _ atomic: inout AtomicInt) -> Bool {
        atomic.lock(); defer { atomic.unlock() }
        if atomic.value == l {
            atomic.value = r
            return true
        }

        return false
    }

    extension Thread {

        static func setThreadLocalStorageValue<T: AnyObject>(_ value: T?, forKey key: String) {
            let currentThread = Thread.current
            var threadDictionary = currentThread.threadDictionary

            if let newValue = value {
                threadDictionary[key] = newValue
            }
            else {
                threadDictionary[key] = nil
            }

            currentThread.threadDictionary = threadDictionary
        }

        static func getThreadLocalStorageValueForKey<T: AnyObject>(_ key: String) -> T? {
            let currentThread = Thread.current
            let threadDictionary = currentThread.threadDictionary

            return threadDictionary[key] as? T
        }
    }

#endif
