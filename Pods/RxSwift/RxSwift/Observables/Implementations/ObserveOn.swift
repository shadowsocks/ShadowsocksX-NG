//
//  ObserveOn.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 7/25/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

final class ObserveOn<E> : Producer<E> {
    let scheduler: ImmediateSchedulerType
    let source: Observable<E>
    
    init(source: Observable<E>, scheduler: ImmediateSchedulerType) {
        self.scheduler = scheduler
        self.source = source
        
#if TRACE_RESOURCES
        let _ = Resources.incrementTotal()
#endif
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == E {
        let sink = ObserveOnSink(scheduler: scheduler, observer: observer, cancel: cancel)
        let subscription = source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
    
#if TRACE_RESOURCES
    deinit {
        let _ = Resources.decrementTotal()
    }
#endif
}

enum ObserveOnState : Int32 {
    // pump is not running
    case stopped = 0
    // pump is running
    case running = 1
}

final class ObserveOnSink<O: ObserverType> : ObserverBase<O.E> {
    typealias E = O.E
    
    let _scheduler: ImmediateSchedulerType

    var _lock = SpinLock()
    let _observer: O

    // state
    var _state = ObserveOnState.stopped
    var _queue = Queue<Event<E>>(capacity: 10)

    let _scheduleDisposable = SerialDisposable()
    let _cancel: Cancelable

    init(scheduler: ImmediateSchedulerType, observer: O, cancel: Cancelable) {
        _scheduler = scheduler
        _observer = observer
        _cancel = cancel
    }

    override func onCore(_ event: Event<E>) {
        let shouldStart = _lock.calculateLocked { () -> Bool in
            self._queue.enqueue(event)
            
            switch self._state {
            case .stopped:
                self._state = .running
                return true
            case .running:
                return false
            }
        }
        
        if shouldStart {
            _scheduleDisposable.disposable = self._scheduler.scheduleRecursive((), action: self.run)
        }
    }
    
    func run(_ state: Void, recurse: (Void) -> Void) {
        let (nextEvent, observer) = self._lock.calculateLocked { () -> (Event<E>?, O) in
            if self._queue.count > 0 {
                return (self._queue.dequeue(), self._observer)
            }
            else {
                self._state = .stopped
                return (nil, self._observer)
            }
        }
        
        if let nextEvent = nextEvent, !_cancel.isDisposed {
            observer.on(nextEvent)
            if nextEvent.isStopEvent {
                dispose()
            }
        }
        else {
            return
        }
        
        let shouldContinue = _shouldContinue_synchronized()
        
        if shouldContinue {
            recurse()
        }
    }

    func _shouldContinue_synchronized() -> Bool {
        _lock.lock(); defer { _lock.unlock() } // {
            if self._queue.count > 0 {
                return true
            }
            else {
                self._state = .stopped
                return false
            }
        // }
    }
    
    override func dispose() {
        super.dispose()

        _cancel.dispose()
        _scheduleDisposable.dispose()
    }
}
