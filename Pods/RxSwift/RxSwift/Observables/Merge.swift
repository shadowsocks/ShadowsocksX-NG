//
//  Merge.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/28/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {

    /**
     Projects each element of an observable sequence to an observable sequence and merges the resulting observable sequences into one observable sequence.

     - seealso: [flatMap operator on reactivex.io](http://reactivex.io/documentation/operators/flatmap.html)

     - parameter selector: A transform function to apply to each element.
     - returns: An observable sequence whose elements are the result of invoking the one-to-many transform function on each element of the input sequence.
     */
    public func flatMap<O: ObservableConvertibleType>(_ selector: @escaping (E) throws -> O)
        -> Observable<O.E> {
            return FlatMap(source: self.asObservable(), selector: selector)
    }

}

extension ObservableType {

    /**
     Projects each element of an observable sequence to an observable sequence and merges the resulting observable sequences into one observable sequence.
     If element is received while there is some projected observable sequence being merged it will simply be ignored.

     - seealso: [flatMapFirst operator on reactivex.io](http://reactivex.io/documentation/operators/flatmap.html)

     - parameter selector: A transform function to apply to element that was observed while no observable is executing in parallel.
     - returns: An observable sequence whose elements are the result of invoking the one-to-many transform function on each element of the input sequence that was received while no other sequence was being calculated.
     */
    public func flatMapFirst<O: ObservableConvertibleType>(_ selector: @escaping (E) throws -> O)
        -> Observable<O.E> {
            return FlatMapFirst(source: self.asObservable(), selector: selector)
    }
}

extension ObservableType where E : ObservableConvertibleType {

    /**
     Merges elements from all observable sequences in the given enumerable sequence into a single observable sequence.

     - seealso: [merge operator on reactivex.io](http://reactivex.io/documentation/operators/merge.html)

     - returns: The observable sequence that merges the elements of the observable sequences.
     */
    public func merge() -> Observable<E.E> {
        return Merge(source: self.asObservable())
    }

    /**
     Merges elements from all inner observable sequences into a single observable sequence, limiting the number of concurrent subscriptions to inner sequences.

     - seealso: [merge operator on reactivex.io](http://reactivex.io/documentation/operators/merge.html)

     - parameter maxConcurrent: Maximum number of inner observable sequences being subscribed to concurrently.
     - returns: The observable sequence that merges the elements of the inner sequences.
     */
    public func merge(maxConcurrent: Int)
        -> Observable<E.E> {
        return MergeLimited(source: self.asObservable(), maxConcurrent: maxConcurrent)
    }
}

extension ObservableType where E : ObservableConvertibleType {

    /**
     Concatenates all inner observable sequences, as long as the previous observable sequence terminated successfully.

     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)

     - returns: An observable sequence that contains the elements of each observed inner sequence, in sequential order.
     */
    public func concat() -> Observable<E.E> {
        return self.merge(maxConcurrent: 1)
    }
}

extension ObservableType {
    /**
     Merges elements from all observable sequences from collection into a single observable sequence.

     - seealso: [merge operator on reactivex.io](http://reactivex.io/documentation/operators/merge.html)

     - parameter sources: Collection of observable sequences to merge.
     - returns: The observable sequence that merges the elements of the observable sequences.
     */
    public static func merge<C: Collection>(_ sources: C) -> Observable<E> where C.Iterator.Element == Observable<E> {
        return MergeArray(sources: Array(sources))
    }

    /**
     Merges elements from all observable sequences from array into a single observable sequence.

     - seealso: [merge operator on reactivex.io](http://reactivex.io/documentation/operators/merge.html)

     - parameter sources: Array of observable sequences to merge.
     - returns: The observable sequence that merges the elements of the observable sequences.
     */
    public static func merge(_ sources: [Observable<E>]) -> Observable<E> {
        return MergeArray(sources: sources)
    }

    /**
     Merges elements from all observable sequences into a single observable sequence.

     - seealso: [merge operator on reactivex.io](http://reactivex.io/documentation/operators/merge.html)

     - parameter sources: Collection of observable sequences to merge.
     - returns: The observable sequence that merges the elements of the observable sequences.
     */
    public static func merge(_ sources: Observable<E>...) -> Observable<E> {
        return MergeArray(sources: sources)
    }
}

// MARK: concatMap

extension ObservableType {
    /**
     Projects each element of an observable sequence to an observable sequence and concatenates the resulting observable sequences into one observable sequence.
     
     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)
     
     - returns: An observable sequence that contains the elements of each observed inner sequence, in sequential order.
     */
    
    public func concatMap<O: ObservableConvertibleType>(_ selector: @escaping (E) throws -> O)
        -> Observable<O.E> {
            return ConcatMap(source: self.asObservable(), selector: selector)
    }
}

fileprivate final class MergeLimitedSinkIter<SourceElement, SourceSequence: ObservableConvertibleType, Observer: ObserverType>
    : ObserverType
    , LockOwnerType
    , SynchronizedOnType where SourceSequence.E == Observer.E {
    typealias E = Observer.E
    typealias DisposeKey = CompositeDisposable.DisposeKey
    typealias Parent = MergeLimitedSink<SourceElement, SourceSequence, Observer>
    
    private let _parent: Parent
    private let _disposeKey: DisposeKey

    var _lock: RecursiveLock {
        return self._parent._lock
    }
    
    init(parent: Parent, disposeKey: DisposeKey) {
        self._parent = parent
        self._disposeKey = disposeKey
    }
    
    func on(_ event: Event<E>) {
        self.synchronizedOn(event)
    }

    func _synchronized_on(_ event: Event<E>) {
        switch event {
        case .next:
            self._parent.forwardOn(event)
        case .error:
            self._parent.forwardOn(event)
            self._parent.dispose()
        case .completed:
            self._parent._group.remove(for: self._disposeKey)
            if let next = self._parent._queue.dequeue() {
                self._parent.subscribe(next, group: self._parent._group)
            }
            else {
                self._parent._activeCount -= 1
                
                if self._parent._stopped && self._parent._activeCount == 0 {
                    self._parent.forwardOn(.completed)
                    self._parent.dispose()
                }
            }
        }
    }
}

fileprivate final class ConcatMapSink<SourceElement, SourceSequence: ObservableConvertibleType, Observer: ObserverType>: MergeLimitedSink<SourceElement, SourceSequence, Observer> where Observer.E == SourceSequence.E {
    typealias Selector = (SourceElement) throws -> SourceSequence
    
    private let _selector: Selector
    
    init(selector: @escaping Selector, observer: Observer, cancel: Cancelable) {
        self._selector = selector
        super.init(maxConcurrent: 1, observer: observer, cancel: cancel)
    }
    
    override func performMap(_ element: SourceElement) throws -> SourceSequence {
        return try self._selector(element)
    }
}

fileprivate final class MergeLimitedBasicSink<SourceSequence: ObservableConvertibleType, Observer: ObserverType>: MergeLimitedSink<SourceSequence, SourceSequence, Observer> where Observer.E == SourceSequence.E {
    
    override func performMap(_ element: SourceSequence) throws -> SourceSequence {
        return element
    }
}

private class MergeLimitedSink<SourceElement, SourceSequence: ObservableConvertibleType, Observer: ObserverType>
    : Sink<Observer>
    , ObserverType where Observer.E == SourceSequence.E {
    typealias QueueType = Queue<SourceSequence>

    let _maxConcurrent: Int

    let _lock = RecursiveLock()

    // state
    var _stopped = false
    var _activeCount = 0
    var _queue = QueueType(capacity: 2)
    
    let _sourceSubscription = SingleAssignmentDisposable()
    let _group = CompositeDisposable()
    
    init(maxConcurrent: Int, observer: Observer, cancel: Cancelable) {
        self._maxConcurrent = maxConcurrent
        super.init(observer: observer, cancel: cancel)
    }
    
    func run(_ source: Observable<SourceElement>) -> Disposable {
        _ = self._group.insert(self._sourceSubscription)
        
        let disposable = source.subscribe(self)
        self._sourceSubscription.setDisposable(disposable)
        return self._group
    }
    
    func subscribe(_ innerSource: SourceSequence, group: CompositeDisposable) {
        let subscription = SingleAssignmentDisposable()
        
        let key = group.insert(subscription)
        
        if let key = key {
            let observer = MergeLimitedSinkIter(parent: self, disposeKey: key)
            
            let disposable = innerSource.asObservable().subscribe(observer)
            subscription.setDisposable(disposable)
        }
    }
    
    func performMap(_ element: SourceElement) throws -> SourceSequence {
        rxAbstractMethod()
    }

    @inline(__always)
    final private func nextElementArrived(element: SourceElement) -> SourceSequence? {
        self._lock.lock(); defer { self._lock.unlock() } // {
            let subscribe: Bool
            if self._activeCount < self._maxConcurrent {
                self._activeCount += 1
                subscribe = true
            }
            else {
                do {
                    let value = try self.performMap(element)
                    self._queue.enqueue(value)
                } catch {
                    self.forwardOn(.error(error))
                    self.dispose()
                }
                subscribe = false
            }

            if subscribe {
                do {
                    return try self.performMap(element)
                } catch {
                    self.forwardOn(.error(error))
                    self.dispose()
                }
            }

            return nil
        // }
    }

    func on(_ event: Event<SourceElement>) {
        switch event {
        case .next(let element):
            if let sequence = self.nextElementArrived(element: element) {
                self.subscribe(sequence, group: self._group)
            }
        case .error(let error):
            self._lock.lock(); defer { self._lock.unlock() }

            self.forwardOn(.error(error))
            self.dispose()
        case .completed:
            self._lock.lock(); defer { self._lock.unlock() }

            if self._activeCount == 0 {
                self.forwardOn(.completed)
                self.dispose()
            }
            else {
                self._sourceSubscription.dispose()
            }

            self._stopped = true
        }
    }
}

final private class MergeLimited<SourceSequence: ObservableConvertibleType>: Producer<SourceSequence.E> {
    private let _source: Observable<SourceSequence>
    private let _maxConcurrent: Int
    
    init(source: Observable<SourceSequence>, maxConcurrent: Int) {
        self._source = source
        self._maxConcurrent = maxConcurrent
    }
    
    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == SourceSequence.E {
        let sink = MergeLimitedBasicSink<SourceSequence, O>(maxConcurrent: self._maxConcurrent, observer: observer, cancel: cancel)
        let subscription = sink.run(self._source)
        return (sink: sink, subscription: subscription)
    }
}

// MARK: Merge

fileprivate final class MergeBasicSink<S: ObservableConvertibleType, O: ObserverType> : MergeSink<S, S, O> where O.E == S.E {
    override func performMap(_ element: S) throws -> S {
        return element
    }
}

// MARK: flatMap

fileprivate final class FlatMapSink<SourceElement, SourceSequence: ObservableConvertibleType, Observer: ObserverType> : MergeSink<SourceElement, SourceSequence, Observer> where Observer.E == SourceSequence.E {
    typealias Selector = (SourceElement) throws -> SourceSequence

    private let _selector: Selector

    init(selector: @escaping Selector, observer: Observer, cancel: Cancelable) {
        self._selector = selector
        super.init(observer: observer, cancel: cancel)
    }

    override func performMap(_ element: SourceElement) throws -> SourceSequence {
        return try self._selector(element)
    }
}

// MARK: FlatMapFirst

fileprivate final class FlatMapFirstSink<SourceElement, SourceSequence: ObservableConvertibleType, Observer: ObserverType> : MergeSink<SourceElement, SourceSequence, Observer> where Observer.E == SourceSequence.E {
    typealias Selector = (SourceElement) throws -> SourceSequence

    private let _selector: Selector

    override var subscribeNext: Bool {
        return self._activeCount == 0
    }

    init(selector: @escaping Selector, observer: Observer, cancel: Cancelable) {
        self._selector = selector
        super.init(observer: observer, cancel: cancel)
    }

    override func performMap(_ element: SourceElement) throws -> SourceSequence {
        return try self._selector(element)
    }
}

fileprivate final class MergeSinkIter<SourceElement, SourceSequence: ObservableConvertibleType, Observer: ObserverType> : ObserverType where Observer.E == SourceSequence.E {
    typealias Parent = MergeSink<SourceElement, SourceSequence, Observer>
    typealias DisposeKey = CompositeDisposable.DisposeKey
    typealias E = Observer.E
    
    private let _parent: Parent
    private let _disposeKey: DisposeKey

    init(parent: Parent, disposeKey: DisposeKey) {
        self._parent = parent
        self._disposeKey = disposeKey
    }
    
    func on(_ event: Event<E>) {
        self._parent._lock.lock(); defer { self._parent._lock.unlock() } // lock {
            switch event {
            case .next(let value):
                self._parent.forwardOn(.next(value))
            case .error(let error):
                self._parent.forwardOn(.error(error))
                self._parent.dispose()
            case .completed:
                self._parent._group.remove(for: self._disposeKey)
                self._parent._activeCount -= 1
                self._parent.checkCompleted()
            }
        // }
    }
}


private class MergeSink<SourceElement, SourceSequence: ObservableConvertibleType, Observer: ObserverType>
    : Sink<Observer>
    , ObserverType where Observer.E == SourceSequence.E {
    typealias ResultType = Observer.E
    typealias Element = SourceElement

    let _lock = RecursiveLock()

    var subscribeNext: Bool {
        return true
    }

    // state
    let _group = CompositeDisposable()
    let _sourceSubscription = SingleAssignmentDisposable()

    var _activeCount = 0
    var _stopped = false

    override init(observer: Observer, cancel: Cancelable) {
        super.init(observer: observer, cancel: cancel)
    }

    func performMap(_ element: SourceElement) throws -> SourceSequence {
        rxAbstractMethod()
    }

    @inline(__always)
    final private func nextElementArrived(element: SourceElement) -> SourceSequence? {
        self._lock.lock(); defer { self._lock.unlock() } // {
            if !self.subscribeNext {
                return nil
            }

            do {
                let value = try self.performMap(element)
                self._activeCount += 1
                return value
            }
            catch let e {
                self.forwardOn(.error(e))
                self.dispose()
                return nil
            }
        // }
    }
    
    func on(_ event: Event<SourceElement>) {
        switch event {
        case .next(let element):
            if let value = self.nextElementArrived(element: element) {
                self.subscribeInner(value.asObservable())
            }
        case .error(let error):
            self._lock.lock(); defer { self._lock.unlock() }
            self.forwardOn(.error(error))
            self.dispose()
        case .completed:
            self._lock.lock(); defer { self._lock.unlock() }
            self._stopped = true
            self._sourceSubscription.dispose()
            self.checkCompleted()
        }
    }

    func subscribeInner(_ source: Observable<Observer.E>) {
        let iterDisposable = SingleAssignmentDisposable()
        if let disposeKey = self._group.insert(iterDisposable) {
            let iter = MergeSinkIter(parent: self, disposeKey: disposeKey)
            let subscription = source.subscribe(iter)
            iterDisposable.setDisposable(subscription)
        }
    }

    func run(_ sources: [Observable<Observer.E>]) -> Disposable {
        self._activeCount += sources.count

        for source in sources {
            self.subscribeInner(source)
        }

        self._stopped = true

        self.checkCompleted()

        return self._group
    }

    @inline(__always)
    func checkCompleted() {
        if self._stopped && self._activeCount == 0 {
            self.forwardOn(.completed)
            self.dispose()
        }
    }
    
    func run(_ source: Observable<SourceElement>) -> Disposable {
        _ = self._group.insert(self._sourceSubscription)

        let subscription = source.subscribe(self)
        self._sourceSubscription.setDisposable(subscription)
        
        return self._group
    }
}

// MARK: Producers

final private class FlatMap<SourceElement, SourceSequence: ObservableConvertibleType>: Producer<SourceSequence.E> {
    typealias Selector = (SourceElement) throws -> SourceSequence

    private let _source: Observable<SourceElement>
    
    private let _selector: Selector

    init(source: Observable<SourceElement>, selector: @escaping Selector) {
        self._source = source
        self._selector = selector
    }
    
    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == SourceSequence.E {
        let sink = FlatMapSink(selector: self._selector, observer: observer, cancel: cancel)
        let subscription = sink.run(self._source)
        return (sink: sink, subscription: subscription)
    }
}

final private class FlatMapFirst<SourceElement, SourceSequence: ObservableConvertibleType>: Producer<SourceSequence.E> {
    typealias Selector = (SourceElement) throws -> SourceSequence

    private let _source: Observable<SourceElement>

    private let _selector: Selector

    init(source: Observable<SourceElement>, selector: @escaping Selector) {
        self._source = source
        self._selector = selector
    }

    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == SourceSequence.E {
        let sink = FlatMapFirstSink<SourceElement, SourceSequence, O>(selector: self._selector, observer: observer, cancel: cancel)
        let subscription = sink.run(self._source)
        return (sink: sink, subscription: subscription)
    }
}

final class ConcatMap<SourceElement, SourceSequence: ObservableConvertibleType>: Producer<SourceSequence.E> {
    typealias Selector = (SourceElement) throws -> SourceSequence
    
    private let _source: Observable<SourceElement>
    private let _selector: Selector
    
    init(source: Observable<SourceElement>, selector: @escaping Selector) {
        self._source = source
        self._selector = selector
    }
    
    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == SourceSequence.E {
        let sink = ConcatMapSink<SourceElement, SourceSequence, O>(selector: self._selector, observer: observer, cancel: cancel)
        let subscription = sink.run(self._source)
        return (sink: sink, subscription: subscription)
    }
}

final class Merge<SourceSequence: ObservableConvertibleType> : Producer<SourceSequence.E> {
    private let _source: Observable<SourceSequence>

    init(source: Observable<SourceSequence>) {
        self._source = source
    }
    
    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == SourceSequence.E {
        let sink = MergeBasicSink<SourceSequence, O>(observer: observer, cancel: cancel)
        let subscription = sink.run(self._source)
        return (sink: sink, subscription: subscription)
    }
}

final private class MergeArray<Element>: Producer<Element> {
    private let _sources: [Observable<Element>]

    init(sources: [Observable<Element>]) {
        self._sources = sources
    }

    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == E {
        let sink = MergeBasicSink<Observable<E>, O>(observer: observer, cancel: cancel)
        let subscription = sink.run(self._sources)
        return (sink: sink, subscription: subscription)
    }
}
