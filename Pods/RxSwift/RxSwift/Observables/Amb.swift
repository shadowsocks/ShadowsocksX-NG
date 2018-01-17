//
//  Amb.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 6/14/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension Observable {
    /**
     Propagates the observable sequence that reacts first.

     - seealso: [amb operator on reactivex.io](http://reactivex.io/documentation/operators/amb.html)

     - returns: An observable sequence that surfaces any of the given sequences, whichever reacted first.
     */
    public static func amb<S: Sequence>(_ sequence: S) -> Observable<Element>
        where S.Iterator.Element == Observable<Element> {
            return sequence.reduce(Observable<S.Iterator.Element.E>.never()) { a, o in
                return a.amb(o.asObservable())
            }
    }
}

extension ObservableType {

    /**
     Propagates the observable sequence that reacts first.

     - seealso: [amb operator on reactivex.io](http://reactivex.io/documentation/operators/amb.html)

     - parameter right: Second observable sequence.
     - returns: An observable sequence that surfaces either of the given sequences, whichever reacted first.
     */
    public func amb<O2: ObservableType>
        (_ right: O2)
        -> Observable<E> where O2.E == E {
        return Amb(left: asObservable(), right: right.asObservable())
    }
}

fileprivate enum AmbState {
    case neither
    case left
    case right
}

final fileprivate class AmbObserver<O: ObserverType> : ObserverType {
    typealias Element = O.E
    typealias Parent = AmbSink<O>
    typealias This = AmbObserver<O>
    typealias Sink = (This, Event<Element>) -> Void
    
    fileprivate let _parent: Parent
    fileprivate var _sink: Sink
    fileprivate var _cancel: Disposable
    
    init(parent: Parent, cancel: Disposable, sink: @escaping Sink) {
#if TRACE_RESOURCES
        let _ = Resources.incrementTotal()
#endif
        
        _parent = parent
        _sink = sink
        _cancel = cancel
    }
    
    func on(_ event: Event<Element>) {
        _sink(self, event)
        if event.isStopEvent {
            _cancel.dispose()
        }
    }
    
    deinit {
#if TRACE_RESOURCES
        let _ = Resources.decrementTotal()
#endif
    }
}

final fileprivate class AmbSink<O: ObserverType> : Sink<O> {
    typealias ElementType = O.E
    typealias Parent = Amb<ElementType>
    typealias AmbObserverType = AmbObserver<O>

    private let _parent: Parent
    
    private let _lock = RecursiveLock()
    // state
    private var _choice = AmbState.neither
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        _parent = parent
        super.init(observer: observer, cancel: cancel)
    }
    
    func run() -> Disposable {
        let subscription1 = SingleAssignmentDisposable()
        let subscription2 = SingleAssignmentDisposable()
        let disposeAll = Disposables.create(subscription1, subscription2)
        
        let forwardEvent = { (o: AmbObserverType, event: Event<ElementType>) -> Void in
            self.forwardOn(event)
            if event.isStopEvent {
                self.dispose()
            }
        }

        let decide = { (o: AmbObserverType, event: Event<ElementType>, me: AmbState, otherSubscription: Disposable) in
            self._lock.performLocked {
                if self._choice == .neither {
                    self._choice = me
                    o._sink = forwardEvent
                    o._cancel = disposeAll
                    otherSubscription.dispose()
                }
                
                if self._choice == me {
                    self.forwardOn(event)
                    if event.isStopEvent {
                        self.dispose()
                    }
                }
            }
        }
        
        let sink1 = AmbObserver(parent: self, cancel: subscription1) { o, e in
            decide(o, e, .left, subscription2)
        }
        
        let sink2 = AmbObserver(parent: self, cancel: subscription1) { o, e in
            decide(o, e, .right, subscription1)
        }
        
        subscription1.setDisposable(_parent._left.subscribe(sink1))
        subscription2.setDisposable(_parent._right.subscribe(sink2))
        
        return disposeAll
    }
}

final fileprivate class Amb<Element>: Producer<Element> {
    fileprivate let _left: Observable<Element>
    fileprivate let _right: Observable<Element>
    
    init(left: Observable<Element>, right: Observable<Element>) {
        _left = left
        _right = right
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        let sink = AmbSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}
