//
//  SubscribeOn.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 6/14/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {
    /**
     Wraps the source sequence in order to run its subscription and unsubscription logic on the specified
     scheduler.

     This operation is not commonly used.

     This only performs the side-effects of subscription and unsubscription on the specified scheduler.

     In order to invoke observer callbacks on a `scheduler`, use `observeOn`.

     - seealso: [subscribeOn operator on reactivex.io](http://reactivex.io/documentation/operators/subscribeon.html)

     - parameter scheduler: Scheduler to perform subscription and unsubscription actions on.
     - returns: The source sequence whose subscriptions and unsubscriptions happen on the specified scheduler.
     */
    public func subscribe(on scheduler: ImmediateSchedulerType)
        -> Observable<Element> {
        SubscribeOn(source: self, scheduler: scheduler)
    }

    /**
     Wraps the source sequence in order to run its subscription and unsubscription logic on the specified
     scheduler.

     This operation is not commonly used.

     This only performs the side-effects of subscription and unsubscription on the specified scheduler.

     In order to invoke observer callbacks on a `scheduler`, use `observeOn`.

     - seealso: [subscribeOn operator on reactivex.io](http://reactivex.io/documentation/operators/subscribeon.html)

     - parameter scheduler: Scheduler to perform subscription and unsubscription actions on.
     - returns: The source sequence whose subscriptions and unsubscriptions happen on the specified scheduler.
     */
    @available(*, deprecated, renamed: "subscribe(on:)")
    public func subscribeOn(_ scheduler: ImmediateSchedulerType)
        -> Observable<Element> {
        subscribe(on: scheduler)
    }
}

final private class SubscribeOnSink<Ob: ObservableType, Observer: ObserverType>: Sink<Observer>, ObserverType where Ob.Element == Observer.Element {
    typealias Element = Observer.Element 
    typealias Parent = SubscribeOn<Ob>
    
    let parent: Parent
    
    init(parent: Parent, observer: Observer, cancel: Cancelable) {
        self.parent = parent
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<Element>) {
        self.forwardOn(event)
        
        if event.isStopEvent {
            self.dispose()
        }
    }
    
    func run() -> Disposable {
        let disposeEverything = SerialDisposable()
        let cancelSchedule = SingleAssignmentDisposable()
        
        disposeEverything.disposable = cancelSchedule
        
        let disposeSchedule = self.parent.scheduler.schedule(()) { _ -> Disposable in
            let subscription = self.parent.source.subscribe(self)
            disposeEverything.disposable = ScheduledDisposable(scheduler: self.parent.scheduler, disposable: subscription)
            return Disposables.create()
        }

        cancelSchedule.setDisposable(disposeSchedule)
    
        return disposeEverything
    }
}

final private class SubscribeOn<Ob: ObservableType>: Producer<Ob.Element> {
    let source: Ob
    let scheduler: ImmediateSchedulerType
    
    init(source: Ob, scheduler: ImmediateSchedulerType) {
        self.source = source
        self.scheduler = scheduler
    }
    
    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == Ob.Element {
        let sink = SubscribeOnSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}
