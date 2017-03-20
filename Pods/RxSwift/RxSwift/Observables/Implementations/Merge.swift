//
//  Merge.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/28/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

// MARK: Limited concurrency version

fileprivate final class MergeLimitedSinkIter<S: ObservableConvertibleType, O: ObserverType>
    : ObserverType
    , LockOwnerType
    , SynchronizedOnType where S.E == O.E {
    typealias E = O.E
    typealias DisposeKey = CompositeDisposable.DisposeKey
    typealias Parent = MergeLimitedSink<S, O>
    
    private let _parent: Parent
    private let _disposeKey: DisposeKey

    var _lock: RecursiveLock {
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

fileprivate final class MergeLimitedSink<S: ObservableConvertibleType, O: ObserverType>
    : Sink<O>
    , ObserverType
    , LockOwnerType
    , SynchronizedOnType where S.E == O.E {
    typealias E = S
    typealias QueueType = Queue<S>

    let _maxConcurrent: Int

    let _lock = RecursiveLock()

    // state
    var _stopped = false
    var _activeCount = 0
    var _queue = QueueType(capacity: 2)
    
    let _sourceSubscription = SingleAssignmentDisposable()
    let _group = CompositeDisposable()
    
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

final class MergeLimited<S: ObservableConvertibleType> : Producer<S.E> {
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

fileprivate final class MergeBasicSink<S: ObservableConvertibleType, O: ObserverType> : MergeSink<S, S, O> where O.E == S.E {
    override init(observer: O, cancel: Cancelable) {
        super.init(observer: observer, cancel: cancel)
    }

    override func performMap(_ element: S) throws -> S {
        return element
    }
}

// MARK: flatMap

fileprivate final class FlatMapSink<SourceType, S: ObservableConvertibleType, O: ObserverType> : MergeSink<SourceType, S, O> where O.E == S.E {
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

fileprivate final class FlatMapWithIndexSink<SourceType, S: ObservableConvertibleType, O: ObserverType> : MergeSink<SourceType, S, O> where O.E == S.E {
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

fileprivate final class FlatMapFirstSink<SourceType, S: ObservableConvertibleType, O: ObserverType> : MergeSink<SourceType, S, O> where O.E == S.E {
    typealias Selector = (SourceType) throws -> S

    private let _selector: Selector

    override var subscribeNext: Bool {
        return _activeCount == 0
    }

    init(selector: @escaping Selector, observer: O, cancel: Cancelable) {
        _selector = selector
        super.init(observer: observer, cancel: cancel)
    }

    override func performMap(_ element: SourceType) throws -> S {
        return try _selector(element)
    }
}

fileprivate final class MergeSinkIter<SourceType, S: ObservableConvertibleType, O: ObserverType> : ObserverType where O.E == S.E {
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
        _parent._lock.lock(); defer { _parent._lock.unlock() } // lock {
            switch event {
            case .next(let value):
                _parent.forwardOn(.next(value))
            case .error(let error):
                _parent.forwardOn(.error(error))
                _parent.dispose()
            case .completed:
                _parent._group.remove(for: _disposeKey)
                _parent._activeCount -= 1
                _parent.checkCompleted()
            }
        // }
    }
}


fileprivate class MergeSink<SourceType, S: ObservableConvertibleType, O: ObserverType>
    : Sink<O>
    , ObserverType where O.E == S.E {
    typealias ResultType = O.E
    typealias Element = SourceType

    let _lock = RecursiveLock()

    var subscribeNext: Bool {
        return true
    }

    // state
    let _group = CompositeDisposable()
    let _sourceSubscription = SingleAssignmentDisposable()

    var _activeCount = 0
    var _stopped = false

    override init(observer: O, cancel: Cancelable) {
        super.init(observer: observer, cancel: cancel)
    }

    func performMap(_ element: SourceType) throws -> S {
        rxAbstractMethod()
    }
    
    func on(_ event: Event<SourceType>) {
        _lock.lock(); defer { _lock.unlock() } // lock {
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
                forwardOn(.error(error))
                dispose()
            case .completed:
                _stopped = true
                _sourceSubscription.dispose()
                checkCompleted()
            }
        //}
    }

    func subscribeInner(_ source: Observable<O.E>) {
        let iterDisposable = SingleAssignmentDisposable()
        if let disposeKey = _group.insert(iterDisposable) {
            _activeCount += 1
            let iter = MergeSinkIter(parent: self, disposeKey: disposeKey)
            let subscription = source.subscribe(iter)
            iterDisposable.setDisposable(subscription)
        }
    }

    func run(_ sources: [SourceType]) -> Disposable {
        let _ = _group.insert(_sourceSubscription)
        _stopped = true

        for source in sources {
            self.on(.next(source))
        }

        checkCompleted()

        return _group
    }

    @inline(__always)
    func checkCompleted() {
        if _stopped && _activeCount == 0 {
            self.forwardOn(.completed)
            self.dispose()
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

final class MergeArray<E> : Producer<E> {
    private let _sources: [Observable<E>]

    init(sources: [Observable<E>]) {
        _sources = sources
    }

    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == E {
        let sink = MergeBasicSink<Observable<E>, O>(observer: observer, cancel: cancel)
        let subscription = sink.run(_sources)
        return (sink: sink, subscription: subscription)
    }
}
