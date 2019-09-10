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
        -> Observable<[E]> {
        return BufferTimeCount(source: self.asObservable(), timeSpan: timeSpan, count: count, scheduler: scheduler)
    }
}

final private class BufferTimeCount<Element>: Producer<[Element]> {
    
    fileprivate let _timeSpan: RxTimeInterval
    fileprivate let _count: Int
    fileprivate let _scheduler: SchedulerType
    fileprivate let _source: Observable<Element>
    
    init(source: Observable<Element>, timeSpan: RxTimeInterval, count: Int, scheduler: SchedulerType) {
        self._source = source
        self._timeSpan = timeSpan
        self._count = count
        self._scheduler = scheduler
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == [Element] {
        let sink = BufferTimeCountSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}

final private class BufferTimeCountSink<Element, O: ObserverType>
    : Sink<O>
    , LockOwnerType
    , ObserverType
    , SynchronizedOnType where O.E == [Element] {
    typealias Parent = BufferTimeCount<Element>
    typealias E = Element
    
    private let _parent: Parent
    
    let _lock = RecursiveLock()
    
    // state
    private let _timerD = SerialDisposable()
    private var _buffer = [Element]()
    private var _windowID = 0
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        self._parent = parent
        super.init(observer: observer, cancel: cancel)
    }
 
    func run() -> Disposable {
        self.createTimer(self._windowID)
        return Disposables.create(_timerD, _parent._source.subscribe(self))
    }
    
    func startNewWindowAndSendCurrentOne() {
        self._windowID = self._windowID &+ 1
        let windowID = self._windowID
        
        let buffer = self._buffer
        self._buffer = []
        self.forwardOn(.next(buffer))
        
        self.createTimer(windowID)
    }
    
    func on(_ event: Event<E>) {
        self.synchronizedOn(event)
    }

    func _synchronized_on(_ event: Event<E>) {
        switch event {
        case .next(let element):
            self._buffer.append(element)
            
            if self._buffer.count == self._parent._count {
                self.startNewWindowAndSendCurrentOne()
            }
            
        case .error(let error):
            self._buffer = []
            self.forwardOn(.error(error))
            self.dispose()
        case .completed:
            self.forwardOn(.next(self._buffer))
            self.forwardOn(.completed)
            self.dispose()
        }
    }
    
    func createTimer(_ windowID: Int) {
        if self._timerD.isDisposed {
            return
        }
        
        if self._windowID != windowID {
            return
        }

        let nextTimer = SingleAssignmentDisposable()
        
        self._timerD.disposable = nextTimer

        let disposable = self._parent._scheduler.scheduleRelative(windowID, dueTime: self._parent._timeSpan) { previousWindowID in
            self._lock.performLocked {
                if previousWindowID != self._windowID {
                    return
                }
             
                self.startNewWindowAndSendCurrentOne()
            }
            
            return Disposables.create()
        }

        nextTimer.setDisposable(disposable)
    }
}
