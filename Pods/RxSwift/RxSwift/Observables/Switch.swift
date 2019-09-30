//
//  Switch.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/12/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {
    /**
     Projects each element of an observable sequence into a new sequence of observable sequences and then
     transforms an observable sequence of observable sequences into an observable sequence producing values only from the most recent observable sequence.

     It is a combination of `map` + `switchLatest` operator

     - seealso: [flatMapLatest operator on reactivex.io](http://reactivex.io/documentation/operators/flatmap.html)

     - parameter selector: A transform function to apply to each element.
     - returns: An observable sequence whose elements are the result of invoking the transform function on each element of source producing an
     Observable of Observable sequences and that at any point in time produces the elements of the most recent inner observable sequence that has been received.
     */
    public func flatMapLatest<O: ObservableConvertibleType>(_ selector: @escaping (E) throws -> O)
        -> Observable<O.E> {
            return FlatMapLatest(source: self.asObservable(), selector: selector)
    }
}

extension ObservableType where E : ObservableConvertibleType {

    /**
     Transforms an observable sequence of observable sequences into an observable sequence
     producing values only from the most recent observable sequence.

     Each time a new inner observable sequence is received, unsubscribe from the
     previous inner observable sequence.

     - seealso: [switch operator on reactivex.io](http://reactivex.io/documentation/operators/switch.html)

     - returns: The observable sequence that at any point in time produces the elements of the most recent inner observable sequence that has been received.
     */
    public func switchLatest() -> Observable<E.E> {
        return Switch(source: self.asObservable())
    }
}

private class SwitchSink<SourceType, S: ObservableConvertibleType, O: ObserverType>
    : Sink<O>
    , ObserverType where S.E == O.E {
    typealias E = SourceType

    fileprivate let _subscriptions: SingleAssignmentDisposable = SingleAssignmentDisposable()
    fileprivate let _innerSubscription: SerialDisposable = SerialDisposable()

    let _lock = RecursiveLock()
    
    // state
    fileprivate var _stopped = false
    fileprivate var _latest = 0
    fileprivate var _hasLatest = false
    
    override init(observer: O, cancel: Cancelable) {
        super.init(observer: observer, cancel: cancel)
    }
    
    func run(_ source: Observable<SourceType>) -> Disposable {
        let subscription = source.subscribe(self)
        self._subscriptions.setDisposable(subscription)
        return Disposables.create(_subscriptions, _innerSubscription)
    }

    func performMap(_ element: SourceType) throws -> S {
        rxAbstractMethod()
    }

    @inline(__always)
    final private func nextElementArrived(element: E) -> (Int, Observable<S.E>)? {
        self._lock.lock(); defer { self._lock.unlock() } // {
            do {
                let observable = try self.performMap(element).asObservable()
                self._hasLatest = true
                self._latest = self._latest &+ 1
                return (self._latest, observable)
            }
            catch let error {
                self.forwardOn(.error(error))
                self.dispose()
            }

            return nil
        // }
    }

    func on(_ event: Event<E>) {
        switch event {
        case .next(let element):
            if let (latest, observable) = self.nextElementArrived(element: element) {
                let d = SingleAssignmentDisposable()
                self._innerSubscription.disposable = d
                   
                let observer = SwitchSinkIter(parent: self, id: latest, _self: d)
                let disposable = observable.subscribe(observer)
                d.setDisposable(disposable)
            }
        case .error(let error):
            self._lock.lock(); defer { self._lock.unlock() }
            self.forwardOn(.error(error))
            self.dispose()
        case .completed:
            self._lock.lock(); defer { self._lock.unlock() }
            self._stopped = true
            
            self._subscriptions.dispose()
            
            if !self._hasLatest {
                self.forwardOn(.completed)
                self.dispose()
            }
        }
    }
}

final private class SwitchSinkIter<SourceType, S: ObservableConvertibleType, O: ObserverType>
    : ObserverType
    , LockOwnerType
    , SynchronizedOnType where S.E == O.E {
    typealias E = S.E
    typealias Parent = SwitchSink<SourceType, S, O>
    
    fileprivate let _parent: Parent
    fileprivate let _id: Int
    fileprivate let _self: Disposable

    var _lock: RecursiveLock {
        return self._parent._lock
    }

    init(parent: Parent, id: Int, _self: Disposable) {
        self._parent = parent
        self._id = id
        self._self = _self
    }
    
    func on(_ event: Event<E>) {
        self.synchronizedOn(event)
    }

    func _synchronized_on(_ event: Event<E>) {
        switch event {
        case .next: break
        case .error, .completed:
            self._self.dispose()
        }
        
        if self._parent._latest != self._id {
            return
        }
       
        switch event {
        case .next:
            self._parent.forwardOn(event)
        case .error:
            self._parent.forwardOn(event)
            self._parent.dispose()
        case .completed:
            self._parent._hasLatest = false
            if self._parent._stopped {
                self._parent.forwardOn(event)
                self._parent.dispose()
            }
        }
    }
}

// MARK: Specializations

final private class SwitchIdentitySink<S: ObservableConvertibleType, O: ObserverType>: SwitchSink<S, S, O> where O.E == S.E {
    override init(observer: O, cancel: Cancelable) {
        super.init(observer: observer, cancel: cancel)
    }

    override func performMap(_ element: S) throws -> S {
        return element
    }
}

final private class MapSwitchSink<SourceType, S: ObservableConvertibleType, O: ObserverType>: SwitchSink<SourceType, S, O> where O.E == S.E {
    typealias Selector = (SourceType) throws -> S

    fileprivate let _selector: Selector

    init(selector: @escaping Selector, observer: O, cancel: Cancelable) {
        self._selector = selector
        super.init(observer: observer, cancel: cancel)
    }

    override func performMap(_ element: SourceType) throws -> S {
        return try self._selector(element)
    }
}

// MARK: Producers

final private class Switch<S: ObservableConvertibleType>: Producer<S.E> {
    fileprivate let _source: Observable<S>
    
    init(source: Observable<S>) {
        self._source = source
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == S.E {
        let sink = SwitchIdentitySink<S, O>(observer: observer, cancel: cancel)
        let subscription = sink.run(self._source)
        return (sink: sink, subscription: subscription)
    }
}

final private class FlatMapLatest<SourceType, S: ObservableConvertibleType>: Producer<S.E> {
    typealias Selector = (SourceType) throws -> S

    fileprivate let _source: Observable<SourceType>
    fileprivate let _selector: Selector

    init(source: Observable<SourceType>, selector: @escaping Selector) {
        self._source = source
        self._selector = selector
    }

    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == S.E {
        let sink = MapSwitchSink<SourceType, S, O>(selector: self._selector, observer: observer, cancel: cancel)
        let subscription = sink.run(self._source)
        return (sink: sink, subscription: subscription)
    }
}
