//
//  RecursiveScheduler.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 6/7/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

fileprivate enum ScheduleState {
    case initial
    case added(CompositeDisposable.DisposeKey)
    case done
}

/// Type erased recursive scheduler.
class AnyRecursiveScheduler<State> {
    
    typealias Action =  (State, AnyRecursiveScheduler<State>) -> Void

    private let _lock = NSRecursiveLock()
    
    // state
    private let _group = CompositeDisposable()

    private var _scheduler: SchedulerType
    private var _action: Action?
    
    init(scheduler: SchedulerType, action: @escaping Action) {
        _action = action
        _scheduler = scheduler
    }

    /**
    Schedules an action to be executed recursively.
    
    - parameter state: State passed to the action to be executed.
    - parameter dueTime: Relative time after which to execute the recursive action.
    */
    func schedule(_ state: State, dueTime: RxTimeInterval) {
        var scheduleState: ScheduleState = .initial

        let d = _scheduler.scheduleRelative(state, dueTime: dueTime) { (state) -> Disposable in
            // best effort
            if self._group.isDisposed {
                return Disposables.create()
            }
            
            let action = self._lock.calculateLocked { () -> Action? in
                switch scheduleState {
                case let .added(removeKey):
                    self._group.remove(for: removeKey)
                case .initial:
                    break
                case .done:
                    break
                }

                scheduleState = .done

                return self._action
            }
            
            if let action = action {
                action(state, self)
            }
            
            return Disposables.create()
        }
            
        _lock.performLocked {
            switch scheduleState {
            case .added:
                rxFatalError("Invalid state")
                break
            case .initial:
                if let removeKey = _group.insert(d) {
                    scheduleState = .added(removeKey)
                }
                else {
                    scheduleState = .done
                }
                break
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

        let d = _scheduler.schedule(state) { (state) -> Disposable in
            // best effort
            if self._group.isDisposed {
                return Disposables.create()
            }
            
            let action = self._lock.calculateLocked { () -> Action? in
                switch scheduleState {
                case let .added(removeKey):
                    self._group.remove(for: removeKey)
                case .initial:
                    break
                case .done:
                    break
                }

                scheduleState = .done
                
                return self._action
            }
           
            if let action = action {
                action(state, self)
            }
            
            return Disposables.create()
        }
        
        _lock.performLocked {
            switch scheduleState {
            case .added:
                rxFatalError("Invalid state")
                break
            case .initial:
                if let removeKey = _group.insert(d) {
                    scheduleState = .added(removeKey)
                }
                else {
                    scheduleState = .done
                }
                break
            case .done:
                break
            }
        }
    }
    
    func dispose() {
        _lock.performLocked {
            _action = nil
        }
        _group.dispose()
    }
}

/// Type erased recursive scheduler.
class RecursiveImmediateScheduler<State> {
    typealias Action =  (_ state: State, _ recurse: (State) -> Void) -> Void
    
    private var _lock = SpinLock()
    private let _group = CompositeDisposable()
    
    private var _action: Action?
    private let _scheduler: ImmediateSchedulerType
    
    init(action: @escaping Action, scheduler: ImmediateSchedulerType) {
        _action = action
        _scheduler = scheduler
    }
    
    // immediate scheduling
    
    /// Schedules an action to be executed recursively.
    ///
    /// - parameter state: State passed to the action to be executed.
    func schedule(_ state: State) {
        var scheduleState: ScheduleState = .initial

        let d = _scheduler.schedule(state) { (state) -> Disposable in
            // best effort
            if self._group.isDisposed {
                return Disposables.create()
            }
            
            let action = self._lock.calculateLocked { () -> Action? in
                switch scheduleState {
                case let .added(removeKey):
                    self._group.remove(for: removeKey)
                case .initial:
                    break
                case .done:
                    break
                }

                scheduleState = .done

                return self._action
            }
            
            if let action = action {
                action(state, self.schedule)
            }
            
            return Disposables.create()
        }
        
        _lock.performLocked {
            switch scheduleState {
            case .added:
                rxFatalError("Invalid state")
                break
            case .initial:
                if let removeKey = _group.insert(d) {
                    scheduleState = .added(removeKey)
                }
                else {
                    scheduleState = .done
                }
                break
            case .done:
                break
            }
        }
    }
    
    func dispose() {
        _lock.performLocked {
            _action = nil
        }
        _group.dispose()
    }
}
