//
//  CurrentThreadScheduler.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 8/30/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation
import Dispatch

let CurrentThreadSchedulerKeyInstance       = "RxSwift.CurrentThreadScheduler.SchedulerKey"
let CurrentThreadSchedulerQueueKeyInstance  = "RxSwift.CurrentThreadScheduler.Queue"

typealias CurrentThreadSchedulerValue       = NSString
let CurrentThreadSchedulerValueInstance     = "RxSwift.CurrentThreadScheduler.SchedulerKey" as NSString


/// Represents an object that schedules units of work on the current thread.
///
/// This is the default scheduler for operators that generate elements.
///
/// This scheduler is also sometimes called `trampoline scheduler`.
public class CurrentThreadScheduler : ImmediateSchedulerType {
    typealias ScheduleQueue = RxMutableBox<Queue<ScheduledItemType>>

    /// The singleton instance of the current thread scheduler.
    public static let instance = CurrentThreadScheduler()

    static var queue : ScheduleQueue? {
        get {
            return Thread.getThreadLocalStorageValueForKey(CurrentThreadSchedulerQueueKeyInstance)
        }
        set {
            Thread.setThreadLocalStorageValue(newValue, forKey: CurrentThreadSchedulerQueueKeyInstance)
        }
    }

    /// Gets a value that indicates whether the caller must call a `schedule` method.
    public static fileprivate(set) var isScheduleRequired: Bool {
        get {
            let value: CurrentThreadSchedulerValue? = Thread.getThreadLocalStorageValueForKey(CurrentThreadSchedulerKeyInstance)
            return value == nil
        }
        set(isScheduleRequired) {
            Thread.setThreadLocalStorageValue(isScheduleRequired ? nil : CurrentThreadSchedulerValueInstance, forKey: CurrentThreadSchedulerKeyInstance)
        }
    }

    /**
    Schedules an action to be executed as soon as possible on current thread.

    If this method is called on some thread that doesn't have `CurrentThreadScheduler` installed, scheduler will be
    automatically installed and uninstalled after all work is performed.

    - parameter state: State passed to the action to be executed.
    - parameter action: Action to be executed.
    - returns: The disposable object used to cancel the scheduled action (best effort).
    */
    public func schedule<StateType>(_ state: StateType, action: @escaping (StateType) -> Disposable) -> Disposable {
        if CurrentThreadScheduler.isScheduleRequired {
            CurrentThreadScheduler.isScheduleRequired = false

            let disposable = action(state)

            defer {
                CurrentThreadScheduler.isScheduleRequired = true
                CurrentThreadScheduler.queue = nil
            }

            guard let queue = CurrentThreadScheduler.queue else {
                return disposable
            }

            while let latest = queue.value.dequeue() {
                if latest.isDisposed {
                    continue
                }
                latest.invoke()
            }

            return disposable
        }

        let existingQueue = CurrentThreadScheduler.queue

        let queue: RxMutableBox<Queue<ScheduledItemType>>
        if let existingQueue = existingQueue {
            queue = existingQueue
        }
        else {
            queue = RxMutableBox(Queue<ScheduledItemType>(capacity: 1))
            CurrentThreadScheduler.queue = queue
        }

        let scheduledItem = ScheduledItem(action: action, state: state)
        queue.value.enqueue(scheduledItem)

        return scheduledItem
    }
}
