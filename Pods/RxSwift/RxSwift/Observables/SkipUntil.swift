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
    public func skipUntil<O: ObservableType>(_ other: O)
        -> Observable<E> {
        return SkipUntil(source: asObservable(), other: other.asObservable())
    }
}

final fileprivate class SkipUntilSinkOther<Other, O: ObserverType>
    : ObserverType
    , LockOwnerType
    , SynchronizedOnType {
    typealias Parent = SkipUntilSink<Other, O>
    typealias E = Other
    
    fileprivate let _parent: Parent

    var _lock: RecursiveLock {
        return _parent._lock
    }
    
    let _subscription = SingleAssignmentDisposable()

    init(parent: Parent) {
        _parent = parent
        #if TRACE_RESOURCES
            let _ = Resources.incrementTotal()
        #endif
    }

    func on(_ event: Event<E>) {
        synchronizedOn(event)
    }

    func _synchronized_on(_ event: Event<E>) {
        switch event {
        case .next:
            _parent._forwardElements = true
            _subscription.dispose()
        case .error(let e):
            _parent.forwardOn(.error(e))
            _parent.dispose()
        case .completed:
            _subscription.dispose()
        }
    }
    
    #if TRACE_RESOURCES
    deinit {
        let _ = Resources.decrementTotal()
    }
    #endif

}


final fileprivate class SkipUntilSink<Other, O: ObserverType>
    : Sink<O>
    , ObserverType
    , LockOwnerType
    , SynchronizedOnType {
    typealias E = O.E
    typealias Parent = SkipUntil<E, Other>
    
    let _lock = RecursiveLock()
    fileprivate let _parent: Parent
    fileprivate var _forwardElements = false
    
    fileprivate let _sourceSubscription = SingleAssignmentDisposable()

    init(parent: Parent, observer: O, cancel: Cancelable) {
        _parent = parent
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<E>) {
        synchronizedOn(event)
    }

    func _synchronized_on(_ event: Event<E>) {
        switch event {
        case .next:
            if _forwardElements {
                forwardOn(event)
            }
        case .error:
            forwardOn(event)
            self.dispose()
        case .completed:
            if _forwardElements {
                forwardOn(event)
            }
            self.dispose()
        }
    }
    
    func run() -> Disposable {
        let sourceSubscription = _parent._source.subscribe(self)
        let otherObserver = SkipUntilSinkOther(parent: self)
        let otherSubscription = _parent._other.subscribe(otherObserver)
        _sourceSubscription.setDisposable(sourceSubscription)
        otherObserver._subscription.setDisposable(otherSubscription)
        
        return Disposables.create(_sourceSubscription, otherObserver._subscription)
    }
}

final fileprivate class SkipUntil<Element, Other>: Producer<Element> {
    
    fileprivate let _source: Observable<Element>
    fileprivate let _other: Observable<Other>
    
    init(source: Observable<Element>, other: Observable<Other>) {
        _source = source
        _other = other
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        let sink = SkipUntilSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}
