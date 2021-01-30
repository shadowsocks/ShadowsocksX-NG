//
//  Debounce.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 9/11/16.
//  Copyright © 2016 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {

    /**
     Ignores elements from an observable sequence which are followed by another element within a specified relative time duration, using the specified scheduler to run throttling timers.

     - seealso: [debounce operator on reactivex.io](http://reactivex.io/documentation/operators/debounce.html)

     - parameter dueTime: Throttling duration for each element.
     - parameter scheduler: Scheduler to run the throttle timers on.
     - returns: The throttled sequence.
     */
    public func debounce(_ dueTime: RxTimeInterval, scheduler: SchedulerType)
        -> Observable<Element> {
            return Debounce(source: self.asObservable(), dueTime: dueTime, scheduler: scheduler)
    }
}

final private class DebounceSink<Observer: ObserverType>
    : Sink<Observer>
    , ObserverType
    , LockOwnerType
    , SynchronizedOnType {
    typealias Element = Observer.Element 
    typealias ParentType = Debounce<Element>

    private let _parent: ParentType

    let _lock = RecursiveLock()

    // state
    private var _id = 0 as UInt64
    private var _value: Element?

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
            self._id = self._id &+ 1
            let currentId = self._id
            self._value = element


            let scheduler = self._parent._scheduler
            let dueTime = self._parent._dueTime

            let d = SingleAssignmentDisposable()
            self.cancellable.disposable = d
            d.setDisposable(scheduler.scheduleRelative(currentId, dueTime: dueTime, action: self.propagate))
        case .error:
            self._value = nil
            self.forwardOn(event)
            self.dispose()
        case .completed:
            if let value = self._value {
                self._value = nil
                self.forwardOn(.next(value))
            }
            self.forwardOn(.completed)
            self.dispose()
        }
    }

    func propagate(_ currentId: UInt64) -> Disposable {
        self._lock.lock(); defer { self._lock.unlock() } // {
        let originalValue = self._value

        if let value = originalValue, self._id == currentId {
            self._value = nil
            self.forwardOn(.next(value))
        }
        // }
        return Disposables.create()
    }
}

final private class Debounce<Element>: Producer<Element> {
    fileprivate let _source: Observable<Element>
    fileprivate let _dueTime: RxTimeInterval
    fileprivate let _scheduler: SchedulerType

    init(source: Observable<Element>, dueTime: RxTimeInterval, scheduler: SchedulerType) {
        self._source = source
        self._dueTime = dueTime
        self._scheduler = scheduler
    }

    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == Element {
        let sink = DebounceSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
    
}
