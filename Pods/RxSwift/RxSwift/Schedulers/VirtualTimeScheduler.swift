//
//  VirtualTimeScheduler.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 2/14/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

/// Base class for virtual time schedulers using a priority queue for scheduled items.
open class VirtualTimeScheduler<Converter: VirtualTimeConverterType>
    : SchedulerType {

    public typealias VirtualTime = Converter.VirtualTimeUnit
    public typealias VirtualTimeInterval = Converter.VirtualTimeIntervalUnit

    private var _running : Bool

    private var _clock: VirtualTime

    fileprivate var _schedulerQueue : PriorityQueue<VirtualSchedulerItem<VirtualTime>>
    private var _converter: Converter

    private var _nextId = 0

    /// - returns: Current time.
    public var now: RxTime {
        return self._converter.convertFromVirtualTime(self.clock)
    }

    /// - returns: Scheduler's absolute time clock value.
    public var clock: VirtualTime {
        return self._clock
    }

    /// Creates a new virtual time scheduler.
    ///
    /// - parameter initialClock: Initial value for the clock.
    public init(initialClock: VirtualTime, converter: Converter) {
        self._clock = initialClock
        self._running = false
        self._converter = converter
        self._schedulerQueue = PriorityQueue(hasHigherPriority: {
            switch converter.compareVirtualTime($0.time, $1.time) {
            case .lessThan:
                return true
            case .equal:
                return $0.id < $1.id
            case .greaterThan:
                return false
            }
        }, isEqual: { $0 === $1 })
        #if TRACE_RESOURCES
            _ = Resources.incrementTotal()
        #endif
    }

    /**
    Schedules an action to be executed immediately.

    - parameter state: State passed to the action to be executed.
    - parameter action: Action to be executed.
    - returns: The disposable object used to cancel the scheduled action (best effort).
    */
    public func schedule<StateType>(_ state: StateType, action: @escaping (StateType) -> Disposable) -> Disposable {
        return self.scheduleRelative(state, dueTime: 0.0) { a in
            return action(a)
        }
    }

    /**
     Schedules an action to be executed.

     - parameter state: State passed to the action to be executed.
     - parameter dueTime: Relative time after which to execute the action.
     - parameter action: Action to be executed.
     - returns: The disposable object used to cancel the scheduled action (best effort).
     */
    public func scheduleRelative<StateType>(_ state: StateType, dueTime: RxTimeInterval, action: @escaping (StateType) -> Disposable) -> Disposable {
        let time = self.now.addingTimeInterval(dueTime)
        let absoluteTime = self._converter.convertToVirtualTime(time)
        let adjustedTime = self.adjustScheduledTime(absoluteTime)
        return self.scheduleAbsoluteVirtual(state, time: adjustedTime, action: action)
    }

    /**
     Schedules an action to be executed after relative time has passed.

     - parameter state: State passed to the action to be executed.
     - parameter time: Absolute time when to execute the action. If this is less or equal then `now`, `now + 1`  will be used.
     - parameter action: Action to be executed.
     - returns: The disposable object used to cancel the scheduled action (best effort).
     */
    public func scheduleRelativeVirtual<StateType>(_ state: StateType, dueTime: VirtualTimeInterval, action: @escaping (StateType) -> Disposable) -> Disposable {
        let time = self._converter.offsetVirtualTime(self.clock, offset: dueTime)
        return self.scheduleAbsoluteVirtual(state, time: time, action: action)
    }

    /**
     Schedules an action to be executed at absolute virtual time.

     - parameter state: State passed to the action to be executed.
     - parameter time: Absolute time when to execute the action.
     - parameter action: Action to be executed.
     - returns: The disposable object used to cancel the scheduled action (best effort).
     */
    public func scheduleAbsoluteVirtual<StateType>(_ state: StateType, time: Converter.VirtualTimeUnit, action: @escaping (StateType) -> Disposable) -> Disposable {
        MainScheduler.ensureExecutingOnScheduler()

        let compositeDisposable = CompositeDisposable()

        let item = VirtualSchedulerItem(action: {
            let dispose = action(state)
            return dispose
        }, time: time, id: self._nextId)

        self._nextId += 1

        self._schedulerQueue.enqueue(item)
        
        _ = compositeDisposable.insert(item)
        
        return compositeDisposable
    }

    /// Adjusts time of scheduling before adding item to schedule queue.
    open func adjustScheduledTime(_ time: Converter.VirtualTimeUnit) -> Converter.VirtualTimeUnit {
        return time
    }

    /// Starts the virtual time scheduler.
    public func start() {
        MainScheduler.ensureExecutingOnScheduler()

        if self._running {
            return
        }

        self._running = true
        repeat {
            guard let next = self.findNext() else {
                break
            }

            if self._converter.compareVirtualTime(next.time, self.clock).greaterThan {
                self._clock = next.time
            }

            next.invoke()
            self._schedulerQueue.remove(next)
        } while self._running

        self._running = false
    }

    func findNext() -> VirtualSchedulerItem<VirtualTime>? {
        while let front = self._schedulerQueue.peek() {
            if front.isDisposed {
                self._schedulerQueue.remove(front)
                continue
            }

            return front
        }

        return nil
    }

    /// Advances the scheduler's clock to the specified time, running all work till that point.
    ///
    /// - parameter virtualTime: Absolute time to advance the scheduler's clock to.
    public func advanceTo(_ virtualTime: VirtualTime) {
        MainScheduler.ensureExecutingOnScheduler()

        if self._running {
            fatalError("Scheduler is already running")
        }

        self._running = true
        repeat {
            guard let next = self.findNext() else {
                break
            }

            if self._converter.compareVirtualTime(next.time, virtualTime).greaterThan {
                break
            }

            if self._converter.compareVirtualTime(next.time, self.clock).greaterThan {
                self._clock = next.time
            }

            next.invoke()
            self._schedulerQueue.remove(next)
        } while self._running

        self._clock = virtualTime
        self._running = false
    }

    /// Advances the scheduler's clock by the specified relative time.
    public func sleep(_ virtualInterval: VirtualTimeInterval) {
        MainScheduler.ensureExecutingOnScheduler()

        let sleepTo = self._converter.offsetVirtualTime(self.clock, offset: virtualInterval)
        if self._converter.compareVirtualTime(sleepTo, self.clock).lessThen {
            fatalError("Can't sleep to past.")
        }

        self._clock = sleepTo
    }

    /// Stops the virtual time scheduler.
    public func stop() {
        MainScheduler.ensureExecutingOnScheduler()

        self._running = false
    }

    #if TRACE_RESOURCES
        deinit {
            _ = Resources.decrementTotal()
        }
    #endif
}

// MARK: description

extension VirtualTimeScheduler: CustomDebugStringConvertible {
    /// A textual representation of `self`, suitable for debugging.
    public var debugDescription: String {
        return self._schedulerQueue.debugDescription
    }
}

final class VirtualSchedulerItem<Time>
    : Disposable {
    typealias Action = () -> Disposable
    
    let action: Action
    let time: Time
    let id: Int

    var isDisposed: Bool {
        return self.disposable.isDisposed
    }
    
    var disposable = SingleAssignmentDisposable()
    
    init(action: @escaping Action, time: Time, id: Int) {
        self.action = action
        self.time = time
        self.id = id
    }

    func invoke() {
         self.disposable.setDisposable(self.action())
    }
    
    func dispose() {
        self.disposable.dispose()
    }
}

extension VirtualSchedulerItem
    : CustomDebugStringConvertible {
    var debugDescription: String {
        return "\(self.time)"
    }
}
