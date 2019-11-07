//
//  Platform.Linux.swift
//  Platform
//
//  Created by Krunoslav Zaher on 12/29/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if os(Linux)

    import class Foundation.Thread

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
