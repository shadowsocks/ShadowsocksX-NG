//
//  Timer.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 6/7/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType where Element: RxAbstractInteger {
    /**
     Returns an observable sequence that produces a value after each period, using the specified scheduler to run timers and to send out observer messages.

     - seealso: [interval operator on reactivex.io](http://reactivex.io/documentation/operators/interval.html)

     - parameter period: Period for producing the values in the resulting sequence.
     - parameter scheduler: Scheduler to run the timer on.
     - returns: An observable sequence that produces a value after each period.
     */
    public static func interval(_ period: RxTimeInterval, scheduler: SchedulerType)
        -> Observable<Element> {
        return Timer(
            dueTime: period,
            period: period,
            scheduler: scheduler
        )
    }
}

extension ObservableType where Element: RxAbstractInteger {
    /**
     Returns an observable sequence that periodically produces a value after the specified initial relative due time has elapsed, using the specified scheduler to run timers.

     - seealso: [timer operator on reactivex.io](http://reactivex.io/documentation/operators/timer.html)

     - parameter dueTime: Relative time at which to produce the first value.
     - parameter period: Period to produce subsequent values.
     - parameter scheduler: Scheduler to run timers on.
     - returns: An observable sequence that produces a value after due time has elapsed and then each period.
     */
    public static func timer(_ dueTime: RxTimeInterval, period: RxTimeInterval? = nil, scheduler: SchedulerType)
        -> Observable<Element> {
        return Timer(
            dueTime: dueTime,
            period: period,
            scheduler: scheduler
        )
    }
}

import Foundation

final private class TimerSink<Observer: ObserverType> : Sink<Observer> where Observer.Element : RxAbstractInteger  {
    typealias Parent = Timer<Observer.Element>

    private let parent: Parent
    private let lock = RecursiveLock()

    init(parent: Parent, observer: Observer, cancel: Cancelable) {
        self.parent = parent
        super.init(observer: observer, cancel: cancel)
    }

    func run() -> Disposable {
        return self.parent.scheduler.schedulePeriodic(0 as Observer.Element, startAfter: self.parent.dueTime, period: self.parent.period!) { state in
            self.lock.performLocked {
                self.forwardOn(.next(state))
                return state &+ 1
            }
        }
    }
}

final private class TimerOneOffSink<Observer: ObserverType>: Sink<Observer> where Observer.Element: RxAbstractInteger {
    typealias Parent = Timer<Observer.Element>

    private let parent: Parent

    init(parent: Parent, observer: Observer, cancel: Cancelable) {
        self.parent = parent
        super.init(observer: observer, cancel: cancel)
    }

    func run() -> Disposable {
        return self.parent.scheduler.scheduleRelative(self, dueTime: self.parent.dueTime) { [unowned self] _ -> Disposable in
            self.forwardOn(.next(0))
            self.forwardOn(.completed)
            self.dispose()

            return Disposables.create()
        }
    }
}

final private class Timer<Element: RxAbstractInteger>: Producer<Element> {
    fileprivate let scheduler: SchedulerType
    fileprivate let dueTime: RxTimeInterval
    fileprivate let period: RxTimeInterval?

    init(dueTime: RxTimeInterval, period: RxTimeInterval?, scheduler: SchedulerType) {
        self.scheduler = scheduler
        self.dueTime = dueTime
        self.period = period
    }

    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == Element {
        if self.period != nil {
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
