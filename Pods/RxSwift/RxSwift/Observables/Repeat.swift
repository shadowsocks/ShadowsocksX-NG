//
//  Repeat.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 9/13/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {
    /**
     Generates an observable sequence that repeats the given element infinitely, using the specified scheduler to send out observer messages.

     - seealso: [repeat operator on reactivex.io](http://reactivex.io/documentation/operators/repeat.html)

     - parameter element: Element to repeat.
     - parameter scheduler: Scheduler to run the producer loop on.
     - returns: An observable sequence that repeats the given element infinitely.
     */
    public static func repeatElement(_ element: E, scheduler: ImmediateSchedulerType = CurrentThreadScheduler.instance) -> Observable<E> {
        return RepeatElement(element: element, scheduler: scheduler)
    }
}

final private class RepeatElement<Element>: Producer<Element> {
    fileprivate let _element: Element
    fileprivate let _scheduler: ImmediateSchedulerType
    
    init(element: Element, scheduler: ImmediateSchedulerType) {
        self._element = element
        self._scheduler = scheduler
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        let sink = RepeatElementSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()

        return (sink: sink, subscription: subscription)
    }
}

final private class RepeatElementSink<O: ObserverType>: Sink<O> {
    typealias Parent = RepeatElement<O.E>
    
    private let _parent: Parent
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        self._parent = parent
        super.init(observer: observer, cancel: cancel)
    }
    
    func run() -> Disposable {
        return self._parent._scheduler.scheduleRecursive(self._parent._element) { e, recurse in
            self.forwardOn(.next(e))
            recurse(e)
        }
    }
}
