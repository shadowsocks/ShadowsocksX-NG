//
//  Delay.swift
//  RxSwift
//
//  Created by tarunon on 2016/02/09.
//  Copyright © 2016 Krunoslav Zaher. All rights reserved.
//

import Foundation

extension ObservableType {

    /**
     Returns an observable sequence by the source observable sequence shifted forward in time by a specified delay. Error events from the source observable sequence are not delayed.

     - seealso: [delay operator on reactivex.io](http://reactivex.io/documentation/operators/delay.html)

     - parameter dueTime: Relative time shift of the source by.
     - parameter scheduler: Scheduler to run the subscription delay timer on.
     - returns: the source Observable shifted in time by the specified delay.
     */
    public func delay(_ dueTime: RxTimeInterval, scheduler: SchedulerType)
        -> Observable<Element> {
            return Delay(source: self.asObservable(), dueTime: dueTime, scheduler: scheduler)
    }
}

final private class DelaySink<Observer: ObserverType>
    : Sink<Observer>
    , ObserverType {
    typealias Element = Observer.Element 
    typealias Source = Observable<Element>
    typealias DisposeKey = Bag<Disposable>.KeyType
    
    private let lock = RecursiveLock()

    private let dueTime: RxTimeInterval
    private let scheduler: SchedulerType
    
    private let sourceSubscription = SingleAssignmentDisposable()
    private let cancelable = SerialDisposable()

    // is scheduled some action
    private var active = false
    // is "run loop" on different scheduler running
    private var running = false
    private var errorEvent: Event<Element>?

    // state
    private var queue = Queue<(eventTime: RxTime, event: Event<Element>)>(capacity: 0)
    
    init(observer: Observer, dueTime: RxTimeInterval, scheduler: SchedulerType, cancel: Cancelable) {
        self.dueTime = dueTime
        self.scheduler = scheduler
        super.init(observer: observer, cancel: cancel)
    }

    // All of these complications in this method are caused by the fact that 
    // error should be propagated immediately. Error can be potentially received on different
    // scheduler so this process needs to be synchronized somehow.
    //
    // Another complication is that scheduler is potentially concurrent so internal queue is used.
    func drainQueue(state: (), scheduler: AnyRecursiveScheduler<()>) {
        self.lock.lock()    
        let hasFailed = self.errorEvent != nil
        if !hasFailed {
            self.running = true
        }
        self.lock.unlock()  

        if hasFailed {
            return
        }

        var ranAtLeastOnce = false

        while true {
            self.lock.lock() 
            let errorEvent = self.errorEvent

            let eventToForwardImmediately = ranAtLeastOnce ? nil : self.queue.dequeue()?.event
            let nextEventToScheduleOriginalTime: Date? = ranAtLeastOnce && !self.queue.isEmpty ? self.queue.peek().eventTime : nil

            if errorEvent == nil {
                if eventToForwardImmediately != nil {
                }
                else if nextEventToScheduleOriginalTime != nil {
                    self.running = false
                }
                else {
                    self.running = false
                    self.active = false
                }
            }
            self.lock.unlock() 

            if let errorEvent = errorEvent {
                self.forwardOn(errorEvent)
                self.dispose()
                return
            }
            else {
                if let eventToForwardImmediately = eventToForwardImmediately {
                    ranAtLeastOnce = true
                    self.forwardOn(eventToForwardImmediately)
                    if case .completed = eventToForwardImmediately {
                        self.dispose()
                        return
                    }
                }
                else if let nextEventToScheduleOriginalTime = nextEventToScheduleOriginalTime {
                    scheduler.schedule((), dueTime: self.dueTime.reduceWithSpanBetween(earlierDate: nextEventToScheduleOriginalTime, laterDate: self.scheduler.now))
                    return
                }
                else {
                    return
                }
            }
        }
    }
    
    func on(_ event: Event<Element>) {
        if event.isStopEvent {
            self.sourceSubscription.dispose()
        }

        switch event {
        case .error:
            self.lock.lock()    
            let shouldSendImmediately = !self.running
            self.queue = Queue(capacity: 0)
            self.errorEvent = event
            self.lock.unlock()  

            if shouldSendImmediately {
                self.forwardOn(event)
                self.dispose()
            }
        default:
            self.lock.lock()    
            let shouldSchedule = !self.active
            self.active = true
            self.queue.enqueue((self.scheduler.now, event))
            self.lock.unlock()  

            if shouldSchedule {
                self.cancelable.disposable = self.scheduler.scheduleRecursive((), dueTime: self.dueTime, action: self.drainQueue)
            }
        }
    }
    
    func run(source: Observable<Element>) -> Disposable {
        self.sourceSubscription.setDisposable(source.subscribe(self))
        return Disposables.create(sourceSubscription, cancelable)
    }
}

final private class Delay<Element>: Producer<Element> {
    private let source: Observable<Element>
    private let dueTime: RxTimeInterval
    private let scheduler: SchedulerType
    
    init(source: Observable<Element>, dueTime: RxTimeInterval, scheduler: SchedulerType) {
        self.source = source
        self.dueTime = dueTime
        self.scheduler = scheduler
    }

    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == Element {
        let sink = DelaySink(observer: observer, dueTime: self.dueTime, scheduler: self.scheduler, cancel: cancel)
        let subscription = sink.run(source: self.source)
        return (sink: sink, subscription: subscription)
    }
}
