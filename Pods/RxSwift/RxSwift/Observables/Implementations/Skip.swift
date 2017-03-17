//
//  Skip.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 6/25/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

// count version

class SkipCountSink<O: ObserverType> : Sink<O>, ObserverType {
    typealias Element = O.E
    typealias Parent = SkipCount<Element>
    
    let parent: Parent
    
    var remaining: Int
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        self.parent = parent
        self.remaining = parent.count
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<Element>) {
        switch event {
        case .next(let value):
            
            if remaining <= 0 {
                forwardOn(.next(value))
            }
            else {
                remaining -= 1
            }
        case .error:
            forwardOn(event)
            self.dispose()
        case .completed:
            forwardOn(event)
            self.dispose()
        }
    }
    
}

class SkipCount<Element>: Producer<Element> {
    let source: Observable<Element>
    let count: Int
    
    init(source: Observable<Element>, count: Int) {
        self.source = source
        self.count = count
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        let sink = SkipCountSink(parent: self, observer: observer, cancel: cancel)
        let subscription = source.subscribe(sink)

        return (sink: sink, subscription: subscription)
    }
}

// time version

class SkipTimeSink<ElementType, O: ObserverType> : Sink<O>, ObserverType where O.E == ElementType {
    typealias Parent = SkipTime<ElementType>
    typealias Element = ElementType

    let parent: Parent
    
    // state
    var open = false
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        self.parent = parent
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<Element>) {
        switch event {
        case .next(let value):
            if open {
                forwardOn(.next(value))
            }
        case .error:
            forwardOn(event)
            self.dispose()
        case .completed:
            forwardOn(event)
            self.dispose()
        }
    }
    
    func tick() {
        open = true
    }
    
    func run() -> Disposable {
        let disposeTimer = parent.scheduler.scheduleRelative((), dueTime: self.parent.duration) {
            self.tick()
            return Disposables.create()
        }
        
        let disposeSubscription = parent.source.subscribe(self)
        
        return Disposables.create(disposeTimer, disposeSubscription)
    }
}

class SkipTime<Element>: Producer<Element> {
    let source: Observable<Element>
    let duration: RxTimeInterval
    let scheduler: SchedulerType
    
    init(source: Observable<Element>, duration: RxTimeInterval, scheduler: SchedulerType) {
        self.source = source
        self.scheduler = scheduler
        self.duration = duration
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        let sink = SkipTimeSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}
