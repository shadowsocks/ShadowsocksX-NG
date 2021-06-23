//
//  Optional.swift
//  RxSwift
//
//  Created by tarunon on 2016/12/13.
//  Copyright © 2016 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {
    /**
     Converts a optional to an observable sequence.

     - seealso: [from operator on reactivex.io](http://reactivex.io/documentation/operators/from.html)

     - parameter optional: Optional element in the resulting observable sequence.
     - returns: An observable sequence containing the wrapped value or not from given optional.
     */
    public static func from(optional: Element?) -> Observable<Element> {
        ObservableOptional(optional: optional)
    }

    /**
     Converts a optional to an observable sequence.

     - seealso: [from operator on reactivex.io](http://reactivex.io/documentation/operators/from.html)

     - parameter optional: Optional element in the resulting observable sequence.
     - parameter scheduler: Scheduler to send the optional element on.
     - returns: An observable sequence containing the wrapped value or not from given optional.
     */
    public static func from(optional: Element?, scheduler: ImmediateSchedulerType) -> Observable<Element> {
        ObservableOptionalScheduled(optional: optional, scheduler: scheduler)
    }
}

final private class ObservableOptionalScheduledSink<Observer: ObserverType>: Sink<Observer> {
    typealias Element = Observer.Element 
    typealias Parent = ObservableOptionalScheduled<Element>

    private let parent: Parent

    init(parent: Parent, observer: Observer, cancel: Cancelable) {
        self.parent = parent
        super.init(observer: observer, cancel: cancel)
    }

    func run() -> Disposable {
        return self.parent.scheduler.schedule(self.parent.optional) { (optional: Element?) -> Disposable in
            if let next = optional {
                self.forwardOn(.next(next))
                return self.parent.scheduler.schedule(()) { _ in
                    self.forwardOn(.completed)
                    self.dispose()
                    return Disposables.create()
                }
            } else {
                self.forwardOn(.completed)
                self.dispose()
                return Disposables.create()
            }
        }
    }
}

final private class ObservableOptionalScheduled<Element>: Producer<Element> {
    fileprivate let optional: Element?
    fileprivate let scheduler: ImmediateSchedulerType

    init(optional: Element?, scheduler: ImmediateSchedulerType) {
        self.optional = optional
        self.scheduler = scheduler
    }

    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == Element {
        let sink = ObservableOptionalScheduledSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}

final private class ObservableOptional<Element>: Producer<Element> {
    private let optional: Element?
    
    init(optional: Element?) {
        self.optional = optional
    }
    
    override func subscribe<Observer: ObserverType>(_ observer: Observer) -> Disposable where Observer.Element == Element {
        if let element = self.optional {
            observer.on(.next(element))
        }
        observer.on(.completed)
        return Disposables.create()
    }
}
