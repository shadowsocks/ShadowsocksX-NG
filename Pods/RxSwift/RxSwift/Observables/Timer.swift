//
//  Timer.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 6/7/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension Observable where Element : SignedInteger {
    /**
     Returns an observable sequence that produces a value after each period, using the specified scheduler to run timers and to send out observer messages.

     - seealso: [interval operator on reactivex.io](http://reactivex.io/documentation/operators/interval.html)

     - parameter period: Period for producing the values in the resulting sequence.
     - parameter scheduler: Scheduler to run the timer on.
     - returns: An observable sequence that produces a value after each period.
     */
    public static func interval(_ period: RxTimeInterval, scheduler: SchedulerType)
        -> Observable<E> {
        return Timer(dueTime: period,
                     period: period,
                     scheduler: scheduler
        )
    }
}

extension Observable where Element: SignedInteger {
    /**
     Returns an observable sequence that periodically produces a value after the specified initial relative due time has elapsed, using the specified scheduler to run timers.

     - seealso: [timer operator on reactivex.io](http://reactivex.io/documentation/operators/timer.html)

     - parameter dueTime: Relative time at which to produce the first value.
     - parameter period: Period to produce subsequent values.
     - parameter scheduler: Scheduler to run timers on.
     - returns: An observable sequence that produces a value after due time has elapsed and then each period.
     */
    public static func timer(_ dueTime: RxTimeInterval, period: RxTimeInterval? = nil, scheduler: SchedulerType)
        -> Observable<E> {
        return Timer(
            dueTime: dueTime,
            period: period,
            scheduler: scheduler
        )
    }
}

final fileprivate class TimerSink<O: ObserverType> : Sink<O> where O.E : SignedInteger  {
    typealias Parent = Timer<O.E>
    
    private let _parent: Parent
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        _parent = parent
        super.init(observer: observer, cancel: cancel)
    }
    
    func run() -> Disposable {
        return _parent._scheduler.schedulePeriodic(0 as O.E, startAfter: _parent._dueTime, period: _parent._period!) { state in
            self.forwardOn(.next(state))
            return state &+ 1
        }
    }
}

final fileprivate class TimerOneOffSink<O: ObserverType> : Sink<O> where O.E : SignedInteger {
    typealias Parent = Timer<O.E>
    
    private let _parent: Parent
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        _parent = parent
        super.init(observer: observer, cancel: cancel)
    }
    
    func run() -> Disposable {
        return _parent._scheduler.scheduleRelative(self, dueTime: _parent._dueTime) { (`self`) -> Disposable in
            self.forwardOn(.next(0))
            self.forwardOn(.completed)
            self.dispose()

            return Disposables.create()
        }
    }
}

final fileprivate class Timer<E: SignedInteger>: Producer<E> {
    fileprivate let _scheduler: SchedulerType
    fileprivate let _dueTime: RxTimeInterval
    fileprivate let _period: RxTimeInterval?
    
    init(dueTime: RxTimeInterval, period: RxTimeInterval?, scheduler: SchedulerType) {
        _scheduler = scheduler
        _dueTime = dueTime
        _period = period
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == E {
        if let _ = _period {
            let sink = TimerSink(parent: self, observer: observer, cancel: cancel)
            let subscription = sink.run()
            return (sink: sink, subscription: subscription)
        }
        else {
            let sink = TimerOneOffSink(parent: self, observer: observer, cancel: cancel)
            let subscription = sink.run()
            return (sink: sink, subscription: subscription)
        }
    }
}
