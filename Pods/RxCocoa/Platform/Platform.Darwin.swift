//
//  Platform.Darwin.swift
//  Platform
//
//  Created by Krunoslav Zaher on 12/29/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)

    import Darwin
    import class Foundation.Thread
    import func Foundation.OSAtomicCompareAndSwap32Barrier
    import func Foundation.OSAtomicIncrement32Barrier
    import func Foundation.OSAtomicDecrement32Barrier
    import protocol Foundation.NSCopying

    typealias AtomicInt = Int32

    fileprivate func castToUInt32Pointer(_ pointer: UnsafeMutablePointer<Int32>) -> UnsafeMutablePointer<UInt32> {
        let raw = UnsafeMutableRawPointer(pointer)
        return raw.assumingMemoryBound(to: UInt32.self)
    }

    let AtomicCompareAndSwap = OSAtomicCompareAndSwap32Barrier
    let AtomicIncrement = OSAtomicIncrement32Barrier
    let AtomicDecrement = OSAtomicDecrement32Barrier
    func AtomicOr(_ mask: UInt32, _ theValue : UnsafeMutablePointer<Int32>) -> Int32 {
        return OSAtomicOr32OrigBarrier(mask, castToUInt32Pointer(theValue))
    }
    func AtomicFlagSet(_ mask: UInt32, _ theValue : UnsafeMutablePointer<Int32>) -> Bool {
        // just used to create a barrier
        OSAtomicXor32OrigBarrier(0, castToUInt32Pointer(theValue))
        return (theValue.pointee & Int32(mask)) != 0
    }

    extension Thread {

        static func setThreadLocalStorageValue<T: AnyObject>(_ value: T?, forKey key: NSCopying
            ) {
            let currentThread = Thread.current
            let threadDictionary = currentThread.threadDictionary

            if let newValue = value {
                threadDictionary[key] = newValue
            }
            else {
                threadDictionary[key] = nil
            }

        }
        static func getThreadLocalStorageValueForKey<T>(_ key: NSCopying) -> T? {
            let currentThread = Thread.current
            let threadDictionary = currentThread.threadDictionary
            
            return threadDictionary[key] as? T
        }
    }

    extension AtomicInt {
        func valueSnapshot() -> Int32 {
            return self
        }
    }
    
#endif
