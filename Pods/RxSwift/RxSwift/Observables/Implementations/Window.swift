//
//  Window.swift
//  RxSwift
//
//  Created by Junior B. on 29/10/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

final class WindowTimeCountSink<Element, O: ObserverType>
    : Sink<O>
    , ObserverType
    , LockOwnerType
    , SynchronizedOnType where O.E == Observable<Element> {
    typealias Parent = WindowTimeCount<Element>
    typealias E = Element
    
    private let _parent: Parent
    
    let _lock = RecursiveLock()
    
    private var _subject = PublishSubject<Element>()
    private var _count = 0
    private var _windowId = 0
    
    private let _timerD = SerialDisposable()
    private let _refCountDisposable: RefCountDisposable
    private let _groupDisposable = CompositeDisposable()
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        _parent = parent
        
        let _ = _groupDisposable.insert(_timerD)
        
        _refCountDisposable = RefCountDisposable(disposable: _groupDisposable)
        super.init(observer: observer, cancel: cancel)
    }
    
    func run() -> Disposable {
        
        forwardOn(.next(AddRef(source: _subject, refCount: _refCountDisposable).asObservable()))
        createTimer(_windowId)
        
        let _ = _groupDisposable.insert(_parent._source.subscribe(self))
        return _refCountDisposable
    }
    
    func startNewWindowAndCompleteCurrentOne() {
        _subject.on(.completed)
        _subject = PublishSubject<Element>()
        
        forwardOn(.next(AddRef(source: _subject, refCount: _refCountDisposable).asObservable()))
    }

    func on(_ event: Event<E>) {
        synchronizedOn(event)
    }

    func _synchronized_on(_ event: Event<E>) {
        var newWindow = false
        var newId = 0
        
        switch event {
        case .next(let element):
            _subject.on(.next(element))
            
            do {
                let _ = try incrementChecked(&_count)
            } catch (let e) {
                _subject.on(.error(e as Swift.Error))
                dispose()
            }
            
            if (_count == _parent._count) {
                newWindow = true
                _count = 0
                _windowId += 1
                newId = _windowId
                self.startNewWindowAndCompleteCurrentOne()
            }
            
        case .error(let error):
            _subject.on(.error(error))
            forwardOn(.error(error))
            dispose()
        case .completed:
            _subject.on(.completed)
            forwardOn(.completed)
            dispose()
        }

        if newWindow {
            createTimer(newId)
        }
    }
    
    func createTimer(_ windowId: Int) {
        if _timerD.isDisposed {
            return
        }
        
        if _windowId != windowId {
            return
        }

        let nextTimer = SingleAssignmentDisposable()

        _timerD.disposable = nextTimer

        let scheduledRelative = _parent._scheduler.scheduleRelative(windowId, dueTime: _parent._timeSpan) { previousWindowId in
            
            var newId = 0
            
            self._lock.performLocked {
                if previousWindowId != self._windowId {
                    return
                }
                
                self._count = 0
                self._windowId = self._windowId &+ 1
                newId = self._windowId
                self.startNewWindowAndCompleteCurrentOne()
            }
            
            self.createTimer(newId)
            
            return Disposables.create()
        }

        nextTimer.setDisposable(scheduledRelative)
    }
}

final class WindowTimeCount<Element> : Producer<Observable<Element>> {
    
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
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Observable<Element> {
        let sink = WindowTimeCountSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}
