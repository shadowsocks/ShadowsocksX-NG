//
//  Timeout.swift
//  RxSwift
//
//  Created by Tomi Koskinen on 13/11/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

final class TimeoutSink<O: ObserverType>: Sink<O>, LockOwnerType, ObserverType {
    typealias E = O.E
    typealias Parent = Timeout<E>
    
    private let _parent: Parent
    
    let _lock = RecursiveLock()

    private let _timerD = SerialDisposable()
    private let _subscription = SerialDisposable()
    
    private var _id = 0
    private var _switched = false
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        _parent = parent
        super.init(observer: observer, cancel: cancel)
    }
    
    func run() -> Disposable {
        let original = SingleAssignmentDisposable()
        _subscription.disposable = original
        
        _createTimeoutTimer()
        
        original.setDisposable(_parent._source.subscribe(self))
        
        return Disposables.create(_subscription, _timerD)
    }

    func on(_ event: Event<E>) {
        switch event {
        case .next:
            var onNextWins = false
            
            _lock.performLocked() {
                onNextWins = !self._switched
                if onNextWins {
                    self._id = self._id &+ 1
                }
            }
            
            if onNextWins {
                forwardOn(event)
                self._createTimeoutTimer()
            }
        case .error, .completed:
            var onEventWins = false
            
            _lock.performLocked() {
                onEventWins = !self._switched
                if onEventWins {
                    self._id = self._id &+ 1
                }
            }
            
            if onEventWins {
                forwardOn(event)
                self.dispose()
            }
        }
    }
    
    private func _createTimeoutTimer() {
        if _timerD.isDisposed {
            return
        }
        
        let nextTimer = SingleAssignmentDisposable()
        _timerD.disposable = nextTimer
        
        let disposeSchedule = _parent._scheduler.scheduleRelative(_id, dueTime: _parent._dueTime) { state in
            
            var timerWins = false
            
            self._lock.performLocked() {
                self._switched = (state == self._id)
                timerWins = self._switched
            }
            
            if timerWins {
                self._subscription.disposable = self._parent._other.subscribe(self.forwarder())
            }
            
            return Disposables.create()
        }

        nextTimer.setDisposable(disposeSchedule)
    }
}


final class Timeout<Element> : Producer<Element> {
    
    fileprivate let _source: Observable<Element>
    fileprivate let _dueTime: RxTimeInterval
    fileprivate let _other: Observable<Element>
    fileprivate let _scheduler: SchedulerType
    
    init(source: Observable<Element>, dueTime: RxTimeInterval, other: Observable<Element>, scheduler: SchedulerType) {
        _source = source
        _dueTime = dueTime
        _other = other
        _scheduler = scheduler
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        let sink = TimeoutSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}
