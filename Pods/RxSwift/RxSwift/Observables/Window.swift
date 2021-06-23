//
//  Window.swift
//  RxSwift
//
//  Created by Junior B. on 29/10/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {

    /**
     Projects each element of an observable sequence into a window that is completed when either it’s full or a given amount of time has elapsed.

     - seealso: [window operator on reactivex.io](http://reactivex.io/documentation/operators/window.html)

     - parameter timeSpan: Maximum time length of a window.
     - parameter count: Maximum element count of a window.
     - parameter scheduler: Scheduler to run windowing timers on.
     - returns: An observable sequence of windows (instances of `Observable`).
     */
    public func window(timeSpan: RxTimeInterval, count: Int, scheduler: SchedulerType)
        -> Observable<Observable<Element>> {
            return WindowTimeCount(source: self.asObservable(), timeSpan: timeSpan, count: count, scheduler: scheduler)
    }
}

final private class WindowTimeCountSink<Element, Observer: ObserverType>
    : Sink<Observer>
    , ObserverType
    , LockOwnerType
    , SynchronizedOnType where Observer.Element == Observable<Element> {
    typealias Parent = WindowTimeCount<Element>
    
    private let parent: Parent
    
    let lock = RecursiveLock()
    
    private var subject = PublishSubject<Element>()
    private var count = 0
    private var windowId = 0
    
    private let timerD = SerialDisposable()
    private let refCountDisposable: RefCountDisposable
    private let groupDisposable = CompositeDisposable()
    
    init(parent: Parent, observer: Observer, cancel: Cancelable) {
        self.parent = parent
        
        _ = self.groupDisposable.insert(self.timerD)
        
        self.refCountDisposable = RefCountDisposable(disposable: self.groupDisposable)
        super.init(observer: observer, cancel: cancel)
    }
    
    func run() -> Disposable {
        
        self.forwardOn(.next(AddRef(source: self.subject, refCount: self.refCountDisposable).asObservable()))
        self.createTimer(self.windowId)
        
        _ = self.groupDisposable.insert(self.parent.source.subscribe(self))
        return self.refCountDisposable
    }
    
    func startNewWindowAndCompleteCurrentOne() {
        self.subject.on(.completed)
        self.subject = PublishSubject<Element>()
        
        self.forwardOn(.next(AddRef(source: self.subject, refCount: self.refCountDisposable).asObservable()))
    }

    func on(_ event: Event<Element>) {
        self.synchronizedOn(event)
    }

    func synchronized_on(_ event: Event<Element>) {
        var newWindow = false
        var newId = 0
        
        switch event {
        case .next(let element):
            self.subject.on(.next(element))
            
            do {
                _ = try incrementChecked(&self.count)
            } catch let e {
                self.subject.on(.error(e as Swift.Error))
                self.dispose()
            }
            
            if self.count == self.parent.count {
                newWindow = true
                self.count = 0
                self.windowId += 1
                newId = self.windowId
                self.startNewWindowAndCompleteCurrentOne()
            }
            
        case .error(let error):
            self.subject.on(.error(error))
            self.forwardOn(.error(error))
            self.dispose()
        case .completed:
            self.subject.on(.completed)
            self.forwardOn(.completed)
            self.dispose()
        }

        if newWindow {
            self.createTimer(newId)
        }
    }
    
    func createTimer(_ windowId: Int) {
        if self.timerD.isDisposed {
            return
        }
        
        if self.windowId != windowId {
            return
        }

        let nextTimer = SingleAssignmentDisposable()

        self.timerD.disposable = nextTimer

        let scheduledRelative = self.parent.scheduler.scheduleRelative(windowId, dueTime: self.parent.timeSpan) { previousWindowId in
            
            var newId = 0
            
            self.lock.performLocked {
                if previousWindowId != self.windowId {
                    return
                }
                
                self.count = 0
                self.windowId = self.windowId &+ 1
                newId = self.windowId
                self.startNewWindowAndCompleteCurrentOne()
            }
            
            self.createTimer(newId)
            
            return Disposables.create()
        }

        nextTimer.setDisposable(scheduledRelative)
    }
}

final private class WindowTimeCount<Element>: Producer<Observable<Element>> {
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
    
    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == Observable<Element> {
        let sink = WindowTimeCountSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}
