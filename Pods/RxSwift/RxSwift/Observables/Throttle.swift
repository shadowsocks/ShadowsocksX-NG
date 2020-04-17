//
//  Throttle.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/22/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import struct Foundation.Date

extension ObservableType {

    /**
     Returns an Observable that emits the first and the latest item emitted by the source Observable during sequential time windows of a specified duration.

     This operator makes sure that no two elements are emitted in less then dueTime.

     - seealso: [debounce operator on reactivex.io](http://reactivex.io/documentation/operators/debounce.html)

     - parameter dueTime: Throttling duration for each element.
     - parameter latest: Should latest element received in a dueTime wide time window since last element emission be emitted.
     - parameter scheduler: Scheduler to run the throttle timers on.
     - returns: The throttled sequence.
     */
    public func throttle(_ dueTime: RxTimeInterval, latest: Bool = true, scheduler: SchedulerType)
        -> Observable<Element> {
        return Throttle(source: self.asObservable(), dueTime: dueTime, latest: latest, scheduler: scheduler)
    }
}

final private class ThrottleSink<Observer: ObserverType>
    : Sink<Observer>
    , ObserverType
    , LockOwnerType
    , SynchronizedOnType {
    typealias Element = Observer.Element 
    typealias ParentType = Throttle<Element>
    
    private let _parent: ParentType
    
    let _lock = RecursiveLock()
    
    // state
    private var _lastUnsentElement: Element?
    private var _lastSentTime: Date?
    private var _completed: Bool = false

    let cancellable = SerialDisposable()
    
    init(parent: ParentType, observer: Observer, cancel: Cancelable) {
        self._parent = parent
        
        super.init(observer: observer, cancel: cancel)
    }
    
    func run() -> Disposable {
        let subscription = self._parent._source.subscribe(self)
        
        return Disposables.create(subscription, cancellable)
    }

    func on(_ event: Event<Element>) {
        self.synchronizedOn(event)
    }

    func _synchronized_on(_ event: Event<Element>) {
        switch event {
        case .next(let element):
            let now = self._parent._scheduler.now

            let reducedScheduledTime: RxTimeInterval

            if let lastSendingTime = self._lastSentTime {
                reducedScheduledTime = self._parent._dueTime.reduceWithSpanBetween(earlierDate: lastSendingTime, laterDate: now)
            }
            else {
                reducedScheduledTime = .nanoseconds(0)
            }

            if reducedScheduledTime.isNow {
                self.sendNow(element: element)
                return
            }

            if !self._parent._latest {
                return
            }

            let isThereAlreadyInFlightRequest = self._lastUnsentElement != nil
            
            self._lastUnsentElement = element

            if isThereAlreadyInFlightRequest {
                return
            }

            let scheduler = self._parent._scheduler

            let d = SingleAssignmentDisposable()
            self.cancellable.disposable = d

            d.setDisposable(scheduler.scheduleRelative(0, dueTime: reducedScheduledTime, action: self.propagate))
        case .error:
            self._lastUnsentElement = nil
            self.forwardOn(event)
            self.dispose()
        case .completed:
            if self._lastUnsentElement != nil {
                self._completed = true
            }
            else {
                self.forwardOn(.completed)
                self.dispose()
            }
        }
    }

    private func sendNow(element: Element) {
        self._lastUnsentElement = nil
        self.forwardOn(.next(element))
        // in case element processing takes a while, this should give some more room
        self._lastSentTime = self._parent._scheduler.now
    }
    
    func propagate(_: Int) -> Disposable {
        self._lock.lock(); defer { self._lock.unlock() } // {
            if let lastUnsentElement = self._lastUnsentElement {
                self.sendNow(element: lastUnsentElement)
            }

            if self._completed {
                self.forwardOn(.completed)
                self.dispose()
            }
        // }
        return Disposables.create()
    }
}

final private class Throttle<Element>: Producer<Element> {
    fileprivate let _source: Observable<Element>
    fileprivate let _dueTime: RxTimeInterval
    fileprivate let _latest: Bool
    fileprivate let _scheduler: SchedulerType

    init(source: Observable<Element>, dueTime: RxTimeInterval, latest: Bool, scheduler: SchedulerType) {
        self._source = source
        self._dueTime = dueTime
        self._latest = latest
        self._scheduler = scheduler
    }
    
    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == Element {
        let sink = ThrottleSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
    
}
