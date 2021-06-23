//
//  RecursiveScheduler.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 6/7/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

private enum ScheduleState {
    case initial
    case added(CompositeDisposable.DisposeKey)
    case done
}

/// Type erased recursive scheduler.
final class AnyRecursiveScheduler<State> {
    
    typealias Action =  (State, AnyRecursiveScheduler<State>) -> Void

    private let lock = RecursiveLock()
    
    // state
    private let group = CompositeDisposable()

    private var scheduler: SchedulerType
    private var action: Action?
    
    init(scheduler: SchedulerType, action: @escaping Action) {
        self.action = action
        self.scheduler = scheduler
    }

    /**
    Schedules an action to be executed recursively.
    
    - parameter state: State passed to the action to be executed.
    - parameter dueTime: Relative time after which to execute the recursive action.
    */
    func schedule(_ state: State, dueTime: RxTimeInterval) {
        var scheduleState: ScheduleState = .initial

        let d = self.scheduler.scheduleRelative(state, dueTime: dueTime) { state -> Disposable in
            // best effort
            if self.group.isDisposed {
                return Disposables.create()
            }
            
            let action = self.lock.performLocked { () -> Action? in
                switch scheduleState {
                case let .added(removeKey):
                    self.group.remove(for: removeKey)
                case .initial:
                    break
                case .done:
                    break
                }

                scheduleState = .done

                return self.action
            }
            
            if let action = action {
                action(state, self)
            }
            
            return Disposables.create()
        }
            
        self.lock.performLocked {
            switch scheduleState {
            case .added:
                rxFatalError("Invalid state")
            case .initial:
                if let removeKey = self.group.insert(d) {
                    scheduleState = .added(removeKey)
                }
                else {
                    scheduleState = .done
                }
            case .done:
                break
            }
        }
    }

    /// Schedules an action to be executed recursively.
    ///
    /// - parameter state: State passed to the action to be executed.
    func schedule(_ state: State) {
        var scheduleState: ScheduleState = .initial

        let d = self.scheduler.schedule(state) { state -> Disposable in
            // best effort
            if self.group.isDisposed {
                return Disposables.create()
            }
            
            let action = self.lock.performLocked { () -> Action? in
                switch scheduleState {
                case let .added(removeKey):
                    self.group.remove(for: removeKey)
                case .initial:
                    break
                case .done:
                    break
                }

                scheduleState = .done
                
                return self.action
            }
           
            if let action = action {
                action(state, self)
            }
            
            return Disposables.create()
        }
        
        self.lock.performLocked {
            switch scheduleState {
            case .added:
                rxFatalError("Invalid state")
            case .initial:
                if let removeKey = self.group.insert(d) {
                    scheduleState = .added(removeKey)
                }
                else {
                    scheduleState = .done
                }
            case .done:
                break
            }
        }
    }
    
    func dispose() {
        self.lock.performLocked {
            self.action = nil
        }
        self.group.dispose()
    }
}

/// Type erased recursive scheduler.
final class RecursiveImmediateScheduler<State> {
    typealias Action =  (_ state: State, _ recurse: (State) -> Void) -> Void
    
    private var lock = SpinLock()
    private let group = CompositeDisposable()
    
    private var action: Action?
    private let scheduler: ImmediateSchedulerType
    
    init(action: @escaping Action, scheduler: ImmediateSchedulerType) {
        self.action = action
        self.scheduler = scheduler
    }
    
    // immediate scheduling
    
    /// Schedules an action to be executed recursively.
    ///
    /// - parameter state: State passed to the action to be executed.
    func schedule(_ state: State) {
        var scheduleState: ScheduleState = .initial

        let d = self.scheduler.schedule(state) { state -> Disposable in
            // best effort
            if self.group.isDisposed {
                return Disposables.create()
            }
            
            let action = self.lock.performLocked { () -> Action? in
                switch scheduleState {
                case let .added(removeKey):
                    self.group.remove(for: removeKey)
                case .initial:
                    break
                case .done:
                    break
                }

                scheduleState = .done

                return self.action
            }
            
            if let action = action {
                action(state, self.schedule)
            }
            
            return Disposables.create()
        }
        
        self.lock.performLocked {
            switch scheduleState {
            case .added:
                rxFatalError("Invalid state")
            case .initial:
                if let removeKey = self.group.insert(d) {
                    scheduleState = .added(removeKey)
                }
                else {
                    scheduleState = .done
                }
            case .done:
                break
            }
        }
    }
    
    func dispose() {
        self.lock.performLocked {
            self.action = nil
        }
        self.group.dispose()
    }
}
