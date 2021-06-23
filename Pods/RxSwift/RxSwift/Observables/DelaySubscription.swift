//
//  DelaySubscription.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 6/14/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {

    /**
     Time shifts the observable sequence by delaying the subscription with the specified relative time duration, using the specified scheduler to run timers.

     - seealso: [delay operator on reactivex.io](http://reactivex.io/documentation/operators/delay.html)

     - parameter dueTime: Relative time shift of the subscription.
     - parameter scheduler: Scheduler to run the subscription delay timer on.
     - returns: Time-shifted sequence.
     */
    public func delaySubscription(_ dueTime: RxTimeInterval, scheduler: SchedulerType)
        -> Observable<Element> {
        DelaySubscription(source: self.asObservable(), dueTime: dueTime, scheduler: scheduler)
    }
}

final private class DelaySubscriptionSink<Observer: ObserverType>
    : Sink<Observer>, ObserverType {
    typealias Element = Observer.Element 
    
    func on(_ event: Event<Element>) {
        self.forwardOn(event)
        if event.isStopEvent {
            self.dispose()
        }
    }
    
}

final private class DelaySubscription<Element>: Producer<Element> {
    private let source: Observable<Element>
    private let dueTime: RxTimeInterval
    private let scheduler: SchedulerType
    
    init(source: Observable<Element>, dueTime: RxTimeInterval, scheduler: SchedulerType) {
        self.source = source
        self.dueTime = dueTime
        self.scheduler = scheduler
    }
    
    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == Element {
        let sink = DelaySubscriptionSink(observer: observer, cancel: cancel)
        let subscription = self.scheduler.scheduleRelative((), dueTime: self.dueTime) { _ in
            return self.source.subscribe(sink)
        }

        return (sink: sink, subscription: subscription)
    }
}
