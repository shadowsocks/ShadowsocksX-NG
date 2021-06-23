//
//  Buffer.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 9/13/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {

    /**
     Projects each element of an observable sequence into a buffer that's sent out when either it's full or a given amount of time has elapsed, using the specified scheduler to run timers.

     A useful real-world analogy of this overload is the behavior of a ferry leaving the dock when all seats are taken, or at the scheduled time of departure, whichever event occurs first.

     - seealso: [buffer operator on reactivex.io](http://reactivex.io/documentation/operators/buffer.html)

     - parameter timeSpan: Maximum time length of a buffer.
     - parameter count: Maximum element count of a buffer.
     - parameter scheduler: Scheduler to run buffering timers on.
     - returns: An observable sequence of buffers.
     */
    public func buffer(timeSpan: RxTimeInterval, count: Int, scheduler: SchedulerType)
        -> Observable<[Element]> {
        BufferTimeCount(source: self.asObservable(), timeSpan: timeSpan, count: count, scheduler: scheduler)
    }
}

final private class BufferTimeCount<Element>: Producer<[Element]> {
    
    fileprivate let timeSpan: RxTimeInterval
    fileprivate let count: Int
    fileprivate let scheduler: SchedulerType
    fileprivate let source: Observable<Element>
    
    init(source: Observable<Element>, timeSpan: RxTimeInterval, count: Int, scheduler: SchedulerType) {
        self.source = source
        self.timeSpan = timeSpan
        self.count = count
        self.scheduler = scheduler
    }
    
    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == [Element] {
        let sink = BufferTimeCountSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}

final private class BufferTimeCountSink<Element, Observer: ObserverType>
    : Sink<Observer>
    , LockOwnerType
    , ObserverType
    , SynchronizedOnType where Observer.Element == [Element] {
    typealias Parent = BufferTimeCount<Element>
    
    private let parent: Parent
    
    let lock = RecursiveLock()
    
    // state
    private let timerD = SerialDisposable()
    private var buffer = [Element]()
    private var windowID = 0
    
    init(parent: Parent, observer: Observer, cancel: Cancelable) {
        self.parent = parent
        super.init(observer: observer, cancel: cancel)
    }
 
    func run() -> Disposable {
        self.createTimer(self.windowID)
        return Disposables.create(timerD, parent.source.subscribe(self))
    }
    
    func startNewWindowAndSendCurrentOne() {
        self.windowID = self.windowID &+ 1
        let windowID = self.windowID
        
        let buffer = self.buffer
        self.buffer = []
        self.forwardOn(.next(buffer))
        
        self.createTimer(windowID)
    }
    
    func on(_ event: Event<Element>) {
        self.synchronizedOn(event)
    }

    func synchronized_on(_ event: Event<Element>) {
        switch event {
        case .next(let element):
            self.buffer.append(element)
            
            if self.buffer.count == self.parent.count {
                self.startNewWindowAndSendCurrentOne()
            }
            
        case .error(let error):
            self.buffer = []
            self.forwardOn(.error(error))
            self.dispose()
        case .completed:
            self.forwardOn(.next(self.buffer))
            self.forwardOn(.completed)
            self.dispose()
        }
    }
    
    func createTimer(_ windowID: Int) {
        if self.timerD.isDisposed {
            return
        }
        
        if self.windowID != windowID {
            return
        }

        let nextTimer = SingleAssignmentDisposable()
        
        self.timerD.disposable = nextTimer

        let disposable = self.parent.scheduler.scheduleRelative(windowID, dueTime: self.parent.timeSpan) { previousWindowID in
            self.lock.performLocked {
                if previousWindowID != self.windowID {
                    return
                }
             
                self.startNewWindowAndSendCurrentOne()
            }
            
            return Disposables.create()
        }

        nextTimer.setDisposable(disposable)
    }
}
