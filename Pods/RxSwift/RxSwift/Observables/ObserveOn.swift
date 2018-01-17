//
//  ObserveOn.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 7/25/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {

    /**
     Wraps the source sequence in order to run its observer callbacks on the specified scheduler.

     This only invokes observer callbacks on a `scheduler`. In case the subscription and/or unsubscription
     actions have side-effects that require to be run on a scheduler, use `subscribeOn`.

     - seealso: [observeOn operator on reactivex.io](http://reactivex.io/documentation/operators/observeon.html)

     - parameter scheduler: Scheduler to notify observers on.
     - returns: The source sequence whose observations happen on the specified scheduler.
     */
    public func observeOn(_ scheduler: ImmediateSchedulerType)
        -> Observable<E> {
            if let scheduler = scheduler as? SerialDispatchQueueScheduler {
                return ObserveOnSerialDispatchQueue(source: self.asObservable(), scheduler: scheduler)
            }
            else {
                return ObserveOn(source: self.asObservable(), scheduler: scheduler)
            }
    }
}

final fileprivate class ObserveOn<E> : Producer<E> {
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

final fileprivate class ObserveOnSink<O: ObserverType> : ObserverBase<O.E> {
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

#if TRACE_RESOURCES
    fileprivate var _numberOfSerialDispatchQueueObservables: AtomicInt = 0
    extension Resources {
        /**
         Counts number of `SerialDispatchQueueObservables`.

         Purposed for unit tests.
         */
        public static var numberOfSerialDispatchQueueObservables: Int32 {
            return _numberOfSerialDispatchQueueObservables.valueSnapshot()
        }
    }
#endif

final fileprivate class ObserveOnSerialDispatchQueueSink<O: ObserverType> : ObserverBase<O.E> {
    let scheduler: SerialDispatchQueueScheduler
    let observer: O

    let cancel: Cancelable

    var cachedScheduleLambda: ((ObserveOnSerialDispatchQueueSink<O>, Event<E>) -> Disposable)!

    init(scheduler: SerialDispatchQueueScheduler, observer: O, cancel: Cancelable) {
        self.scheduler = scheduler
        self.observer = observer
        self.cancel = cancel
        super.init()

        cachedScheduleLambda = { sink, event in
            sink.observer.on(event)

            if event.isStopEvent {
                sink.dispose()
            }

            return Disposables.create()
        }
    }

    override func onCore(_ event: Event<E>) {
        let _ = self.scheduler.schedule((self, event), action: cachedScheduleLambda)
    }

    override func dispose() {
        super.dispose()

        cancel.dispose()
    }
}

final fileprivate class ObserveOnSerialDispatchQueue<E> : Producer<E> {
    let scheduler: SerialDispatchQueueScheduler
    let source: Observable<E>

    init(source: Observable<E>, scheduler: SerialDispatchQueueScheduler) {
        self.scheduler = scheduler
        self.source = source

        #if TRACE_RESOURCES
            let _ = Resources.incrementTotal()
            let _ = AtomicIncrement(&_numberOfSerialDispatchQueueObservables)
        #endif
    }

    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == E {
        let sink = ObserveOnSerialDispatchQueueSink(scheduler: scheduler, observer: observer, cancel: cancel)
        let subscription = source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }

    #if TRACE_RESOURCES
    deinit {
        let _ = Resources.decrementTotal()
        let _ = AtomicDecrement(&_numberOfSerialDispatchQueueObservables)
    }
    #endif
}
