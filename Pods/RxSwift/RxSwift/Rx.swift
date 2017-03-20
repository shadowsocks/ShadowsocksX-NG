//
//  Rx.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 2/14/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if TRACE_RESOURCES
    fileprivate var resourceCount: AtomicInt = 0

    /// Resource utilization information
    public struct Resources {
        /// Counts internal Rx resource allocations (Observables, Observers, Disposables, etc.). This provides a simple way to detect leaks during development.
        public static var total: Int32 {
            return resourceCount.valueSnapshot()
        }

        /// Increments `Resources.total` resource count.
        ///
        /// - returns: New resource count
        public static func incrementTotal() -> Int32 {
            return AtomicIncrement(&resourceCount)
        }

        /// Decrements `Resources.total` resource count
        ///
        /// - returns: New resource count
        public static func decrementTotal() -> Int32 {
            return AtomicDecrement(&resourceCount)
        }
    }
#endif

/// Swift does not implement abstract methods. This method is used as a runtime check to ensure that methods which intended to be abstract (i.e., they should be implemented in subclasses) are not called directly on the superclass.
func rxAbstractMethod(file: StaticString = #file, line: UInt = #line) -> Swift.Never {
    rxFatalError("Abstract method", file: file, line: line)
}

func rxFatalError(_ lastMessage: @autoclosure () -> String, file: StaticString = #file, line: UInt = #line) -> Swift.Never  {
    // The temptation to comment this line is great, but please don't, it's for your own good. The choice is yours.
    fatalError(lastMessage(), file: file, line: line)
}

func rxFatalErrorInDebug(_ lastMessage: @autoclosure () -> String, file: StaticString = #file, line: UInt = #line) {
    #if DEBUG
        fatalError(lastMessage(), file: file, line: line)
    #else
        print("\(file):\(line): \(lastMessage())")
    #endif
}

func incrementChecked(_ i: inout Int) throws -> Int {
    if i == Int.max {
        throw RxError.overflow
    }
    defer { i += 1 }
    return i
}

func decrementChecked(_ i: inout Int) throws -> Int {
    if i == Int.min {
        throw RxError.overflow
    }
    defer { i -= 1 }
    return i
}
