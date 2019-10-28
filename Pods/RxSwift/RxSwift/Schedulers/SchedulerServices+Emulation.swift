//
//  SchedulerServices+Emulation.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 6/6/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

enum SchedulePeriodicRecursiveCommand {
    case tick
    case dispatchStart
}

final class SchedulePeriodicRecursive<State> {
    typealias RecursiveAction = (State) -> State
    typealias RecursiveScheduler = AnyRecursiveScheduler<SchedulePeriodicRecursiveCommand>

    private let _scheduler: SchedulerType
    private let _startAfter: RxTimeInterval
    private let _period: RxTimeInterval
    private let _action: RecursiveAction

    private var _state: State
    private let _pendingTickCount = AtomicInt(0)

    init(scheduler: SchedulerType, startAfter: RxTimeInterval, period: RxTimeInterval, action: @escaping RecursiveAction, state: State) {
        self._scheduler = scheduler
        self._startAfter = startAfter
        self._period = period
        self._action = action
        self._state = state
    }

    func start() -> Disposable {
        return self._scheduler.scheduleRecursive(SchedulePeriodicRecursiveCommand.tick, dueTime: self._startAfter, action: self.tick)
    }

    func tick(_ command: SchedulePeriodicRecursiveCommand, scheduler: RecursiveScheduler) {
        // Tries to emulate periodic scheduling as best as possible.
        // The problem that could arise is if handling periodic ticks take too long, or
        // tick interval is short.
        switch command {
        case .tick:
            scheduler.schedule(.tick, dueTime: self._period)

            // The idea is that if on tick there wasn't any item enqueued, schedule to perform work immediately.
            // Else work will be scheduled after previous enqueued work completes.
            if increment(self._pendingTickCount) == 0 {
                self.tick(.dispatchStart, scheduler: scheduler)
            }

        case .dispatchStart:
            self._state = self._action(self._state)
            // Start work and schedule check is this last batch of work
            if decrement(self._pendingTickCount) > 1 {
                // This gives priority to scheduler emulation, it's not perfect, but helps
                scheduler.schedule(SchedulePeriodicRecursiveCommand.dispatchStart)
            }
        }
    }
}
