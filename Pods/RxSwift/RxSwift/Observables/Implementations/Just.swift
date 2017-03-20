//
//  Just.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 8/30/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

final class JustScheduledSink<O: ObserverType> : Sink<O> {
    typealias Parent = JustScheduled<O.E>

    private let _parent: Parent

    init(parent: Parent, observer: O, cancel: Cancelable) {
        _parent = parent
        super.init(observer: observer, cancel: cancel)
    }

    func run() -> Disposable {
        let scheduler = _parent._scheduler
        return scheduler.schedule(_parent._element) { element in
            self.forwardOn(.next(element))
            return scheduler.schedule(()) { _ in
                self.forwardOn(.completed)
                self.dispose()
                return Disposables.create()
            }
        }
    }
}

final class JustScheduled<Element> : Producer<Element> {
    fileprivate let _scheduler: ImmediateSchedulerType
    fileprivate let _element: Element

    init(element: Element, scheduler: ImmediateSchedulerType) {
        _scheduler = scheduler
        _element = element
    }

    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == E {
        let sink = JustScheduledSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}

final class Just<Element> : Producer<Element> {
    private let _element: Element
    
    init(element: Element) {
        _element = element
    }
    
    override func subscribe<O : ObserverType>(_ observer: O) -> Disposable where O.E == Element {
        observer.on(.next(_element))
        observer.on(.completed)
        return Disposables.create()
    }
}
