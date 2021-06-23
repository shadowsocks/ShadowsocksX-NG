//
//  SkipUntil.swift
//  RxSwift
//
//  Created by Yury Korolev on 10/3/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {
    /**
     Returns the elements from the source observable sequence that are emitted after the other observable sequence produces an element.

     - seealso: [skipUntil operator on reactivex.io](http://reactivex.io/documentation/operators/skipuntil.html)

     - parameter other: Observable sequence that starts propagation of elements of the source sequence.
     - returns: An observable sequence containing the elements of the source sequence that are emitted after the other sequence emits an item.
     */
    public func skip<Source: ObservableType>(until other: Source)
        -> Observable<Element> {
        SkipUntil(source: self.asObservable(), other: other.asObservable())
    }

    /**
     Returns the elements from the source observable sequence that are emitted after the other observable sequence produces an element.

     - seealso: [skipUntil operator on reactivex.io](http://reactivex.io/documentation/operators/skipuntil.html)

     - parameter other: Observable sequence that starts propagation of elements of the source sequence.
     - returns: An observable sequence containing the elements of the source sequence that are emitted after the other sequence emits an item.
     */
    @available(*, deprecated, renamed: "skip(until:)")
    public func skipUntil<Source: ObservableType>(_ other: Source)
        -> Observable<Element> {
        skip(until: other)
    }
}

final private class SkipUntilSinkOther<Other, Observer: ObserverType>
    : ObserverType
    , LockOwnerType
    , SynchronizedOnType {
    typealias Parent = SkipUntilSink<Other, Observer>
    typealias Element = Other
    
    private let parent: Parent

    var lock: RecursiveLock {
        self.parent.lock
    }
    
    let subscription = SingleAssignmentDisposable()

    init(parent: Parent) {
        self.parent = parent
        #if TRACE_RESOURCES
            _ = Resources.incrementTotal()
        #endif
    }

    func on(_ event: Event<Element>) {
        self.synchronizedOn(event)
    }

    func synchronized_on(_ event: Event<Element>) {
        switch event {
        case .next:
            self.parent.forwardElements = true
            self.subscription.dispose()
        case .error(let e):
            self.parent.forwardOn(.error(e))
            self.parent.dispose()
        case .completed:
            self.subscription.dispose()
        }
    }
    
    #if TRACE_RESOURCES
    deinit {
        _ = Resources.decrementTotal()
    }
    #endif

}


final private class SkipUntilSink<Other, Observer: ObserverType>
    : Sink<Observer>
    , ObserverType
    , LockOwnerType
    , SynchronizedOnType {
    typealias Element = Observer.Element 
    typealias Parent = SkipUntil<Element, Other>
    
    let lock = RecursiveLock()
    private let parent: Parent
    fileprivate var forwardElements = false
    
    private let sourceSubscription = SingleAssignmentDisposable()

    init(parent: Parent, observer: Observer, cancel: Cancelable) {
        self.parent = parent
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<Element>) {
        self.synchronizedOn(event)
    }

    func synchronized_on(_ event: Event<Element>) {
        switch event {
        case .next:
            if self.forwardElements {
                self.forwardOn(event)
            }
        case .error:
            self.forwardOn(event)
            self.dispose()
        case .completed:
            if self.forwardElements {
                self.forwardOn(event)
            }
            self.dispose()
        }
    }
    
    func run() -> Disposable {
        let sourceSubscription = self.parent.source.subscribe(self)
        let otherObserver = SkipUntilSinkOther(parent: self)
        let otherSubscription = self.parent.other.subscribe(otherObserver)
        self.sourceSubscription.setDisposable(sourceSubscription)
        otherObserver.subscription.setDisposable(otherSubscription)
        
        return Disposables.create(sourceSubscription, otherObserver.subscription)
    }
}

final private class SkipUntil<Element, Other>: Producer<Element> {
    
    fileprivate let source: Observable<Element>
    fileprivate let other: Observable<Other>
    
    init(source: Observable<Element>, other: Observable<Other>) {
        self.source = source
        self.other = other
    }
    
    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == Element {
        let sink = SkipUntilSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}
