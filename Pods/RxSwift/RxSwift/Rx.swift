//
//  Rx.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 2/14/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if TRACE_RESOURCES
    fileprivate let resourceCount = AtomicInt(0)

    /// Resource utilization information
    public struct Resources {
        /// Counts internal Rx resource allocations (Observables, Observers, Disposables, etc.). This provides a simple way to detect leaks during development.
        public static var total: Int32 {
            return load(resourceCount)
        }

        /// Increments `Resources.total` resource count.
        ///
        /// - returns: New resource count
        public static func incrementTotal() -> Int32 {
            return increment(resourceCount)
        }

        /// Decrements `Resources.total` resource count
        ///
        /// - returns: New resource count
        public static func decrementTotal() -> Int32 {
            return decrement(resourceCount)
        }
    }
#endif

/// Swift does not implement abstract methods. This method is used as a runtime check to ensure that methods which intended to be abstract (i.e., they should be implemented in subclasses) are not called directly on the superclass.
func rxAbstractMethod(file: StaticString = #file, line: UInt = #line) -> Swift.Never {
    rxFatalError("Abstract method", file: file, line: line)
}

func rxFatalError(_ lastMessage: @autoclosure () -> String, file: StaticString = #file, line: UInt = #line) -> Swift.Never  {
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

#if DEBUG
    import class Foundation.Thread
    final class SynchronizationTracker {
        private let _lock = RecursiveLock()

        public enum SynchronizationErrorMessages: String {
            case variable = "Two different threads are trying to assign the same `Variable.value` unsynchronized.\n    This is undefined behavior because the end result (variable value) is nondeterministic and depends on the \n    operating system thread scheduler. This will cause random behavior of your program.\n"
            case `default` = "Two different unsynchronized threads are trying to send some event simultaneously.\n    This is undefined behavior because the ordering of the effects caused by these events is nondeterministic and depends on the \n    operating system thread scheduler. This will result in a random behavior of your program.\n"
        }

        private var _threads = [UnsafeMutableRawPointer: Int]()

        private func synchronizationError(_ message: String) {
            #if FATAL_SYNCHRONIZATION
                rxFatalError(message)
            #else
                print(message)
            #endif
        }
        
        func register(synchronizationErrorMessage: SynchronizationErrorMessages) {
            self._lock.lock(); defer { self._lock.unlock() }
            let pointer = Unmanaged.passUnretained(Thread.current).toOpaque()
            let count = (self._threads[pointer] ?? 0) + 1

            if count > 1 {
                self.synchronizationError(
                    "⚠️ Reentrancy anomaly was detected.\n" +
                    "  > Debugging: To debug this issue you can set a breakpoint in \(#file):\(#line) and observe the call stack.\n" +
                    "  > Problem: This behavior is breaking the observable sequence grammar. `next (error | completed)?`\n" +
                    "    This behavior breaks the grammar because there is overlapping between sequence events.\n" +
                    "    Observable sequence is trying to send an event before sending of previous event has finished.\n" +
                    "  > Interpretation: This could mean that there is some kind of unexpected cyclic dependency in your code,\n" +
                    "    or that the system is not behaving in the expected way.\n" +
                    "  > Remedy: If this is the expected behavior this message can be suppressed by adding `.observeOn(MainScheduler.asyncInstance)`\n" +
                    "    or by enqueuing sequence events in some other way.\n"
                )
            }
            
            self._threads[pointer] = count

            if self._threads.count > 1 {
                self.synchronizationError(
                    "⚠️ Synchronization anomaly was detected.\n" +
                    "  > Debugging: To debug this issue you can set a breakpoint in \(#file):\(#line) and observe the call stack.\n" +
                    "  > Problem: This behavior is breaking the observable sequence grammar. `next (error | completed)?`\n" +
                    "    This behavior breaks the grammar because there is overlapping between sequence events.\n" +
                    "    Observable sequence is trying to send an event before sending of previous event has finished.\n" +
                    "  > Interpretation: " + synchronizationErrorMessage.rawValue +
                    "  > Remedy: If this is the expected behavior this message can be suppressed by adding `.observeOn(MainScheduler.asyncInstance)`\n" +
                    "    or by synchronizing sequence events in some other way.\n"
                )
            }
        }

        func unregister() {
            self._lock.lock(); defer { self._lock.unlock() }
            let pointer = Unmanaged.passUnretained(Thread.current).toOpaque()
            self._threads[pointer] = (self._threads[pointer] ?? 1) - 1
            if self._threads[pointer] == 0 {
                self._threads[pointer] = nil
            }
        }
    }

#endif

/// RxSwift global hooks
public enum Hooks {
    
    // Should capture call stack
    public static var recordCallStackOnError: Bool = false

}
