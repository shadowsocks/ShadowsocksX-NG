//
//  ImmediateScheduler.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 10/17/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

/// Represents an object that schedules units of work to run immediately on the current thread.
private final class ImmediateScheduler : ImmediateSchedulerType {

    private let _asyncLock = AsyncLock<AnonymousInvocable>()

    /**
    Schedules an action to be executed immediatelly.

    In case `schedule` is called recursively from inside of `action` callback, scheduled `action` will be enqueued
    and executed after current `action`. (`AsyncLock` behavior)

    - parameter state: State passed to the action to be executed.
    - parameter action: Action to be executed.
    - returns: The disposable object used to cancel the scheduled action (best effort).
    */
    func schedule<StateType>(_ state: StateType, action: @escaping (StateType) -> Disposable) -> Disposable {
        let disposable = SingleAssignmentDisposable()
        _asyncLock.invoke(AnonymousInvocable {
            if disposable.isDisposed {
                return
            }
            disposable.setDisposable(action(state))
        })

        return disposable
    }
}
