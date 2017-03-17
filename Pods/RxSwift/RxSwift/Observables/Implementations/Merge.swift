//
//  Merge.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/28/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

// MARK: Limited concurrency version

class MergeLimitedSinkIter<S: ObservableConvertibleType, O: ObserverType>
    : ObserverType
    , LockOwnerType
    , SynchronizedOnType where S.E == O.E {
    typealias E = O.E
    typealias DisposeKey = CompositeDisposable.DisposeKey
    typealias Parent = MergeLimitedSink<S, O>
    
    private let _parent: Parent
    private let _disposeKey: DisposeKey

    var _lock: NSRecursiveLock {
        return _parent._lock
    }
    
    init(parent: Parent, disposeKey: DisposeKey) {
        _parent = parent
        _disposeKey = disposeKey
    }
    
    func on(_ event: Event<E>) {
        synchronizedOn(event)
    }

    func _synchronized_on(_ event: Event<E>) {
        switch event {
        case .next:
            _parent.forwardOn(event)
        case .error:
            _parent.forwardOn(event)
            _parent.dispose()
        case .completed:
            _parent._group.remove(for: _disposeKey)
            if let next = _parent._queue.dequeue() {
                _parent.subscribe(next, group: _parent._group)
            }
            else {
                _parent._activeCount = _parent._activeCount - 1
                
                if _parent._stopped && _parent._activeCount == 0 {
                    _parent.forwardOn(.completed)
                    _parent.dispose()
                }
            }
        }
    }
}

class MergeLimitedSink<S: ObservableConvertibleType, O: ObserverType>
    : Sink<O>
    , ObserverType
    , LockOwnerType
    , SynchronizedOnType where S.E == O.E {
    typealias E = S
    typealias QueueType = Queue<S>

    fileprivate let _maxConcurrent: Int

    let _lock = NSRecursiveLock()

    // state
    fileprivate var _stopped = false
    fileprivate var _activeCount = 0
    fileprivate var _queue = QueueType(capacity: 2)
    
    fileprivate let _sourceSubscription = SingleAssignmentDisposable()
    fileprivate let _group = CompositeDisposable()
    
    init(maxConcurrent: Int, observer: O, cancel: Cancelable) {
        _maxConcurrent = maxConcurrent
        
        let _ = _group.insert(_sourceSubscription)
        super.init(observer: observer, cancel: cancel)
    }
    
    func run(_ source: Observable<S>) -> Disposable {
        let _ = _group.insert(_sourceSubscription)
        
        let disposable = source.subscribe(self)
        _sourceSubscription.setDisposable(disposable)
        return _group
    }
    
    func subscribe(_ innerSource: E, group: CompositeDisposable) {
        let subscription = SingleAssignmentDisposable()
        
        let key = group.insert(subscription)
        
        if let key = key {
            let observer = MergeLimitedSinkIter(parent: self, disposeKey: key)
            
            let disposable = innerSource.asObservable().subscribe(observer)
            subscription.setDisposable(disposable)
        }
    }
    
    func on(_ event: Event<E>) {
        synchronizedOn(event)
    }

    func _synchronized_on(_ event: Event<E>) {
        switch event {
        case .next(let value):
            let subscribe: Bool
            if _activeCount < _maxConcurrent {
                _activeCount += 1
                subscribe = true
            }
            else {
                _queue.enqueue(value)
                subscribe = false
            }

            if subscribe {
                self.subscribe(value, group: _group)
            }
        case .error(let error):
            forwardOn(.error(error))
            dispose()
        case .completed:
            if _activeCount == 0 {
                forwardOn(.completed)
                dispose()
            }
            else {
                _sourceSubscription.dispose()
            }
                
            _stopped = true
        }
    }
}

class MergeLimited<S: ObservableConvertibleType> : Producer<S.E> {
    private let _source: Observable<S>
    private let _maxConcurrent: Int
    
    init(source: Observable<S>, maxConcurrent: Int) {
        _source = source
        _maxConcurrent = maxConcurrent
    }
    
    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == S.E {
        let sink = MergeLimitedSink<S, O>(maxConcurrent: _maxConcurrent, observer: observer, cancel: cancel)
        let subscription = sink.run(_source)
        return (sink: sink, subscription: subscription)
    }
}

// MARK: Merge

final class MergeBasicSink<S: ObservableConvertibleType, O: ObserverType> : MergeSink<S, S, O> where O.E == S.E {
    override init(observer: O, cancel: Cancelable) {
        super.init(observer: observer, cancel: cancel)
    }

    override func performMap(_ element: S) throws -> S {
        return element
    }
}

// MARK: flatMap

final class FlatMapSink<SourceType, S: ObservableConvertibleType, O: ObserverType> : MergeSink<SourceType, S, O> where O.E == S.E {
    typealias Selector = (SourceType) throws -> S

    private let _selector: Selector

    init(selector: @escaping Selector, observer: O, cancel: Cancelable) {
        _selector = selector
        super.init(observer: observer, cancel: cancel)
    }

    override func performMap(_ element: SourceType) throws -> S {
        return try _selector(element)
    }
}

final class FlatMapWithIndexSink<SourceType, S: ObservableConvertibleType, O: ObserverType> : MergeSink<SourceType, S, O> where O.E == S.E {
    typealias Selector = (SourceType, Int) throws -> S

    private var _index = 0
    private let _selector: Selector

    init(selector: @escaping Selector, observer: O, cancel: Cancelable) {
        _selector = selector
        super.init(observer: observer, cancel: cancel)
    }

    override func performMap(_ element: SourceType) throws -> S {
        return try _selector(element, try incrementChecked(&_index))
    }
}

// MARK: FlatMapFirst

final class FlatMapFirstSink<SourceType, S: ObservableConvertibleType, O: ObserverType> : MergeSink<SourceType, S, O> where O.E == S.E {
    typealias Selector = (SourceType) throws -> S

    private let _selector: Selector

    override var subscribeNext: Bool {
        return _group.count == MergeNoIterators
    }

    init(selector: @escaping Selector, observer: O, cancel: Cancelable) {
        _selector = selector
        super.init(observer: observer, cancel: cancel)
    }

    override func performMap(_ element: SourceType) throws -> S {
        return try _selector(element)
    }
}

// It's value is one because initial source subscription is always in CompositeDisposable
private let MergeNoIterators = 1

class MergeSinkIter<SourceType, S: ObservableConvertibleType, O: ObserverType> : ObserverType where O.E == S.E {
    typealias Parent = MergeSink<SourceType, S, O>
    typealias DisposeKey = CompositeDisposable.DisposeKey
    typealias E = O.E
    
    private let _parent: Parent
    private let _disposeKey: DisposeKey

    init(parent: Parent, disposeKey: DisposeKey) {
        _parent = parent
        _disposeKey = disposeKey
    }
    
    func on(_ event: Event<E>) {
        switch event {
        case .next(let value):
            _parent._lock.lock(); defer { _parent._lock.unlock() } // lock {
                _parent.forwardOn(.next(value))
            // }
        case .error(let error):
            _parent._lock.lock(); defer { _parent._lock.unlock() } // lock {
                _parent.forwardOn(.error(error))
                _parent.dispose()
            // }
        case .completed:
            _parent._group.remove(for: _disposeKey)
            // If this has returned true that means that `Completed` should be sent.
            // In case there is a race who will sent first completed,
            // lock will sort it out. When first Completed message is sent
            // it will set observer to nil, and thus prevent further complete messages
            // to be sent, and thus preserving the sequence grammar.
            if _parent._stopped && _parent._group.count == MergeNoIterators {
                _parent._lock.lock(); defer { _parent._lock.unlock() } // lock {
                    _parent.forwardOn(.completed)
                    _parent.dispose()
                // }
            }
        }
    }
}


class MergeSink<SourceType, S: ObservableConvertibleType, O: ObserverType>
    : Sink<O>
    , ObserverType where O.E == S.E {
    typealias ResultType = O.E
    typealias Element = SourceType

    fileprivate let _lock = NSRecursiveLock()

    fileprivate var subscribeNext: Bool {
        return true
    }

    // state
    fileprivate let _group = CompositeDisposable()
    fileprivate let _sourceSubscription = SingleAssignmentDisposable()

    fileprivate var _stopped = false

    override init(observer: O, cancel: Cancelable) {
        super.init(observer: observer, cancel: cancel)
    }

    func performMap(_ element: SourceType) throws -> S {
        abstractMethod()
    }
    
    func on(_ event: Event<SourceType>) {
        switch event {
        case .next(let element):
            if !subscribeNext {
                return
            }
            do {
                let value = try performMap(element)
                subscribeInner(value.asObservable())
            }
            catch let e {
                forwardOn(.error(e))
                dispose()
            }
        case .error(let error):
            _lock.lock(); defer { _lock.unlock() } // lock {
                forwardOn(.error(error))
                dispose()
            // }
        case .completed:
            _lock.lock(); defer { _lock.unlock() } // lock {
                _stopped = true
                if _group.count == MergeNoIterators {
                    forwardOn(.completed)
                    dispose()
                }
                else {
                    _sourceSubscription.dispose()
                }
            //}
        }
    }
    
    func subscribeInner(_ source: Observable<O.E>) {
        let iterDisposable = SingleAssignmentDisposable()
        if let disposeKey = _group.insert(iterDisposable) {
            let iter = MergeSinkIter(parent: self, disposeKey: disposeKey)
            let subscription = source.subscribe(iter)
            iterDisposable.setDisposable(subscription)
        }
    }
    
    func run(_ source: Observable<SourceType>) -> Disposable {
        let _ = _group.insert(_sourceSubscription)

        let subscription = source.subscribe(self)
        _sourceSubscription.setDisposable(subscription)
        
        return _group
    }
}

// MARK: Producers

final class FlatMap<SourceType, S: ObservableConvertibleType>: Producer<S.E> {
    typealias Selector = (SourceType) throws -> S

    private let _source: Observable<SourceType>
    
    private let _selector: Selector

    init(source: Observable<SourceType>, selector: @escaping Selector) {
        _source = source
        _selector = selector
    }
    
    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == S.E {
        let sink = FlatMapSink(selector: _selector, observer: observer, cancel: cancel)
        let subscription = sink.run(_source)
        return (sink: sink, subscription: subscription)
    }
}

final class FlatMapWithIndex<SourceType, S: ObservableConvertibleType>: Producer<S.E> {
    typealias Selector = (SourceType, Int) throws -> S

    private let _source: Observable<SourceType>
    
    private let _selector: Selector

    init(source: Observable<SourceType>, selector: @escaping Selector) {
        _source = source
        _selector = selector
    }
    
    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == S.E {
        let sink = FlatMapWithIndexSink<SourceType, S, O>(selector: _selector, observer: observer, cancel: cancel)
        let subscription = sink.run(_source)
        return (sink: sink, subscription: subscription)
    }

}

final class FlatMapFirst<SourceType, S: ObservableConvertibleType>: Producer<S.E> {
    typealias Selector = (SourceType) throws -> S

    private let _source: Observable<SourceType>

    private let _selector: Selector

    init(source: Observable<SourceType>, selector: @escaping Selector) {
        _source = source
        _selector = selector
    }

    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == S.E {
        let sink = FlatMapFirstSink<SourceType, S, O>(selector: _selector, observer: observer, cancel: cancel)
        let subscription = sink.run(_source)
        return (sink: sink, subscription: subscription)
    }
}

final class Merge<S: ObservableConvertibleType> : Producer<S.E> {
    private let _source: Observable<S>

    init(source: Observable<S>) {
        _source = source
    }
    
    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == S.E {
        let sink = MergeBasicSink<S, O>(observer: observer, cancel: cancel)
        let subscription = sink.run(_source)
        return (sink: sink, subscription: subscription)
    }
}

