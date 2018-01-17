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
            return FlatMapLatest(source: asObservable(), selector: selector)
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
        return Switch(source: asObservable())
    }
}

fileprivate class SwitchSink<SourceType, S: ObservableConvertibleType, O: ObserverType>
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
        _subscriptions.setDisposable(subscription)
        return Disposables.create(_subscriptions, _innerSubscription)
    }

    func performMap(_ element: SourceType) throws -> S {
        rxAbstractMethod()
    }

    @inline(__always)
    final private func nextElementArrived(element: E) -> (Int, Observable<S.E>)? {
        _lock.lock(); defer { _lock.unlock() } // {
            do {
                let observable = try performMap(element).asObservable()
                _hasLatest = true
                _latest = _latest &+ 1
                return (_latest, observable)
            }
            catch let error {
                forwardOn(.error(error))
                dispose()
            }

            return nil
        // }
    }

    func on(_ event: Event<E>) {
        switch event {
        case .next(let element):
            if let (latest, observable) = nextElementArrived(element: element) {
                let d = SingleAssignmentDisposable()
                _innerSubscription.disposable = d
                   
                let observer = SwitchSinkIter(parent: self, id: latest, _self: d)
                let disposable = observable.subscribe(observer)
                d.setDisposable(disposable)
            }
        case .error(let error):
            _lock.lock(); defer { _lock.unlock() }
            forwardOn(.error(error))
            dispose()
        case .completed:
            _lock.lock(); defer { _lock.unlock() }
            _stopped = true
            
            _subscriptions.dispose()
            
            if !_hasLatest {
                forwardOn(.completed)
                dispose()
            }
        }
    }
}

final fileprivate class SwitchSinkIter<SourceType, S: ObservableConvertibleType, O: ObserverType>
    : ObserverType
    , LockOwnerType
    , SynchronizedOnType where S.E == O.E {
    typealias E = S.E
    typealias Parent = SwitchSink<SourceType, S, O>
    
    fileprivate let _parent: Parent
    fileprivate let _id: Int
    fileprivate let _self: Disposable

    var _lock: RecursiveLock {
        return _parent._lock
    }

    init(parent: Parent, id: Int, _self: Disposable) {
        _parent = parent
        _id = id
        self._self = _self
    }
    
    func on(_ event: Event<E>) {
        synchronizedOn(event)
    }

    func _synchronized_on(_ event: Event<E>) {
        switch event {
        case .next: break
        case .error, .completed:
            _self.dispose()
        }
        
        if _parent._latest != _id {
            return
        }
       
        switch event {
        case .next:
            _parent.forwardOn(event)
        case .error:
            _parent.forwardOn(event)
            _parent.dispose()
        case .completed:
            _parent._hasLatest = false
            if _parent._stopped {
                _parent.forwardOn(event)
                _parent.dispose()
            }
        }
    }
}

// MARK: Specializations

final fileprivate class SwitchIdentitySink<S: ObservableConvertibleType, O: ObserverType> : SwitchSink<S, S, O> where O.E == S.E {
    override init(observer: O, cancel: Cancelable) {
        super.init(observer: observer, cancel: cancel)
    }

    override func performMap(_ element: S) throws -> S {
        return element
    }
}

final fileprivate class MapSwitchSink<SourceType, S: ObservableConvertibleType, O: ObserverType> : SwitchSink<SourceType, S, O> where O.E == S.E {
    typealias Selector = (SourceType) throws -> S

    fileprivate let _selector: Selector

    init(selector: @escaping Selector, observer: O, cancel: Cancelable) {
        _selector = selector
        super.init(observer: observer, cancel: cancel)
    }

    override func performMap(_ element: SourceType) throws -> S {
        return try _selector(element)
    }
}

// MARK: Producers

final fileprivate class Switch<S: ObservableConvertibleType> : Producer<S.E> {
    fileprivate let _source: Observable<S>
    
    init(source: Observable<S>) {
        _source = source
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == S.E {
        let sink = SwitchIdentitySink<S, O>(observer: observer, cancel: cancel)
        let subscription = sink.run(_source)
        return (sink: sink, subscription: subscription)
    }
}

final fileprivate class FlatMapLatest<SourceType, S: ObservableConvertibleType> : Producer<S.E> {
    typealias Selector = (SourceType) throws -> S

    fileprivate let _source: Observable<SourceType>
    fileprivate let _selector: Selector

    init(source: Observable<SourceType>, selector: @escaping Selector) {
        _source = source
        _selector = selector
    }

    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == S.E {
        let sink = MapSwitchSink<SourceType, S, O>(selector: _selector, observer: observer, cancel: cancel)
        let subscription = sink.run(_source)
        return (sink: sink, subscription: subscription)
    }
}
