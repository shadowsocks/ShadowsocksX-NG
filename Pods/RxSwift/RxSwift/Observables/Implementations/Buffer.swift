//
//  Buffer.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 9/13/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

class BufferTimeCount<Element> : Producer<[Element]> {
    
    fileprivate let _timeSpan: RxTimeInterval
    fileprivate let _count: Int
    fileprivate let _scheduler: SchedulerType
    fileprivate let _source: Observable<Element>
    
    init(source: Observable<Element>, timeSpan: RxTimeInterval, count: Int, scheduler: SchedulerType) {
        _source = source
        _timeSpan = timeSpan
        _count = count
        _scheduler = scheduler
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == [Element] {
        let sink = BufferTimeCountSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}

class BufferTimeCountSink<Element, O: ObserverType>
    : Sink<O>
    , LockOwnerType
    , ObserverType
    , SynchronizedOnType where O.E == [Element] {
    typealias Parent = BufferTimeCount<Element>
    typealias E = Element
    
    private let _parent: Parent
    
    let _lock = NSRecursiveLock()
    
    // state
    private let _timerD = SerialDisposable()
    private var _buffer = [Element]()
    private var _windowID = 0
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        _parent = parent
        super.init(observer: observer, cancel: cancel)
    }
 
    func run() -> Disposable {
        createTimer(_windowID)
        return Disposables.create(_timerD, _parent._source.subscribe(self))
    }
    
    func startNewWindowAndSendCurrentOne() {
        _windowID = _windowID &+ 1
        let windowID = _windowID
        
        let buffer = _buffer
        _buffer = []
        forwardOn(.next(buffer))
        
        createTimer(windowID)
    }
    
    func on(_ event: Event<E>) {
        synchronizedOn(event)
    }

    func _synchronized_on(_ event: Event<E>) {
        switch event {
        case .next(let element):
            _buffer.append(element)
            
            if _buffer.count == _parent._count {
                startNewWindowAndSendCurrentOne()
            }
            
        case .error(let error):
            _buffer = []
            forwardOn(.error(error))
            dispose()
        case .completed:
            forwardOn(.next(_buffer))
            forwardOn(.completed)
            dispose()
        }
    }
    
    func createTimer(_ windowID: Int) {
        if _timerD.isDisposed {
            return
        }
        
        if _windowID != windowID {
            return
        }

        let nextTimer = SingleAssignmentDisposable()
        
        _timerD.disposable = nextTimer

        let disposable = _parent._scheduler.scheduleRelative(windowID, dueTime: _parent._timeSpan) { previousWindowID in
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
