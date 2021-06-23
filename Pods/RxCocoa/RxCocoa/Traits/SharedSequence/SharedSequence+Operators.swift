//
//  SharedSequence+Operators.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 9/19/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import RxSwift

// MARK: map
extension SharedSequenceConvertibleType {
    
    /**
    Projects each element of an observable sequence into a new form.
    
    - parameter selector: A transform function to apply to each source element.
    - returns: An observable sequence whose elements are the result of invoking the transform function on each element of source.
    */
    public func map<Result>(_ selector: @escaping (Element) -> Result) -> SharedSequence<SharingStrategy, Result> {
        let source = self
            .asObservable()
            .map(selector)
        return SharedSequence<SharingStrategy, Result>(source)
    }
}

// MARK: compactMap
extension SharedSequenceConvertibleType {
    
    /**
     Projects each element of an observable sequence into an optional form and filters all optional results.
     
     - parameter transform: A transform function to apply to each source element and which returns an element or nil.
     - returns: An observable sequence whose elements are the result of filtering the transform function for each element of the source.
     
     */
    public func compactMap<Result>(_ selector: @escaping (Element) -> Result?) -> SharedSequence<SharingStrategy, Result> {
        let source = self
            .asObservable()
            .compactMap(selector)
        return SharedSequence<SharingStrategy, Result>(source)
    }
}

// MARK: filter
extension SharedSequenceConvertibleType {
    /**
    Filters the elements of an observable sequence based on a predicate.
    
    - parameter predicate: A function to test each source element for a condition.
    - returns: An observable sequence that contains elements from the input sequence that satisfy the condition.
    */
    public func filter(_ predicate: @escaping (Element) -> Bool) -> SharedSequence<SharingStrategy, Element> {
        let source = self
            .asObservable()
            .filter(predicate)
        return SharedSequence(source)
    }
}

// MARK: switchLatest
extension SharedSequenceConvertibleType where Element: SharedSequenceConvertibleType {
    
    /**
    Transforms an observable sequence of observable sequences into an observable sequence
    producing values only from the most recent observable sequence.
    
    Each time a new inner observable sequence is received, unsubscribe from the
    previous inner observable sequence.
    
    - returns: The observable sequence that at any point in time produces the elements of the most recent inner observable sequence that has been received.
    */
    public func switchLatest() -> SharedSequence<Element.SharingStrategy, Element.Element> {
        let source: Observable<Element.Element> = self
            .asObservable()
            .map { $0.asSharedSequence() }
            .switchLatest()
        return SharedSequence<Element.SharingStrategy, Element.Element>(source)
    }
}

// MARK: flatMapLatest
extension SharedSequenceConvertibleType {
    /**
     Projects each element of an observable sequence into a new sequence of observable sequences and then
     transforms an observable sequence of observable sequences into an observable sequence producing values only from the most recent observable sequence.

     It is a combination of `map` + `switchLatest` operator

     - parameter selector: A transform function to apply to each element.
     - returns: An observable sequence whose elements are the result of invoking the transform function on each element of source producing an
     Observable of Observable sequences and that at any point in time produces the elements of the most recent inner observable sequence that has been received.
     */
    public func flatMapLatest<Sharing, Result>(_ selector: @escaping (Element) -> SharedSequence<Sharing, Result>)
        -> SharedSequence<Sharing, Result> {
        let source: Observable<Result> = self
            .asObservable()
            .flatMapLatest(selector)
        return SharedSequence<Sharing, Result>(source)
    }
}

// MARK: flatMapFirst
extension SharedSequenceConvertibleType {

    /**
     Projects each element of an observable sequence to an observable sequence and merges the resulting observable sequences into one observable sequence.
     If element is received while there is some projected observable sequence being merged it will simply be ignored.

     - parameter selector: A transform function to apply to element that was observed while no observable is executing in parallel.
     - returns: An observable sequence whose elements are the result of invoking the one-to-many transform function on each element of the input sequence that was received while no other sequence was being calculated.
     */
    public func flatMapFirst<Sharing, Result>(_ selector: @escaping (Element) -> SharedSequence<Sharing, Result>)
        -> SharedSequence<Sharing, Result> {
        let source: Observable<Result> = self
            .asObservable()
            .flatMapFirst(selector)
        return SharedSequence<Sharing, Result>(source)
    }
}

// MARK: do
extension SharedSequenceConvertibleType {
    /**
     Invokes an action for each event in the observable sequence, and propagates all observer messages through the result sequence.

     - parameter onNext: Action to invoke for each element in the observable sequence.
     - parameter afterNext: Action to invoke for each element after the observable has passed an onNext event along to its downstream.
     - parameter onCompleted: Action to invoke upon graceful termination of the observable sequence.
     - parameter afterCompleted: Action to invoke after graceful termination of the observable sequence.
     - parameter onSubscribe: Action to invoke before subscribing to source observable sequence.
     - parameter onSubscribed: Action to invoke after subscribing to source observable sequence.
     - parameter onDispose: Action to invoke after subscription to source observable has been disposed for any reason. It can be either because sequence terminates for some reason or observer subscription being disposed.
     - returns: The source sequence with the side-effecting behavior applied.
     */
    public func `do`(onNext: ((Element) -> Void)? = nil, afterNext: ((Element) -> Void)? = nil, onCompleted: (() -> Void)? = nil, afterCompleted: (() -> Void)? = nil, onSubscribe: (() -> Void)? = nil, onSubscribed: (() -> Void)? = nil, onDispose: (() -> Void)? = nil)
        -> SharedSequence<SharingStrategy, Element> {
        let source = self.asObservable()
            .do(onNext: onNext, afterNext: afterNext, onCompleted: onCompleted, afterCompleted: afterCompleted, onSubscribe: onSubscribe, onSubscribed: onSubscribed, onDispose: onDispose)

        return SharedSequence(source)
    }
}

// MARK: debug
extension SharedSequenceConvertibleType {
    
    /**
    Prints received events for all observers on standard output.
    
    - parameter identifier: Identifier that is printed together with event description to standard output.
    - returns: An observable sequence whose events are printed to standard output.
    */
    public func debug(_ identifier: String? = nil, trimOutput: Bool = false, file: String = #file, line: UInt = #line, function: String = #function) -> SharedSequence<SharingStrategy, Element> {
        let source = self.asObservable()
            .debug(identifier, trimOutput: trimOutput, file: file, line: line, function: function)
        return SharedSequence(source)
    }
}

// MARK: distinctUntilChanged
extension SharedSequenceConvertibleType where Element: Equatable {
    
    /**
    Returns an observable sequence that contains only distinct contiguous elements according to equality operator.
    
    - returns: An observable sequence only containing the distinct contiguous elements, based on equality operator, from the source sequence.
    */
    public func distinctUntilChanged()
        -> SharedSequence<SharingStrategy, Element> {
        let source = self.asObservable()
            .distinctUntilChanged({ $0 }, comparer: { ($0 == $1) })
            
        return SharedSequence(source)
    }
}

extension SharedSequenceConvertibleType {
    
    /**
    Returns an observable sequence that contains only distinct contiguous elements according to the `keySelector`.
    
    - parameter keySelector: A function to compute the comparison key for each element.
    - returns: An observable sequence only containing the distinct contiguous elements, based on a computed key value, from the source sequence.
    */
    public func distinctUntilChanged<Key: Equatable>(_ keySelector: @escaping (Element) -> Key) -> SharedSequence<SharingStrategy, Element> {
        let source = self.asObservable()
            .distinctUntilChanged(keySelector, comparer: { $0 == $1 })
        return SharedSequence(source)
    }
   
    /**
    Returns an observable sequence that contains only distinct contiguous elements according to the `comparer`.
    
    - parameter comparer: Equality comparer for computed key values.
    - returns: An observable sequence only containing the distinct contiguous elements, based on `comparer`, from the source sequence.
    */
    public func distinctUntilChanged(_ comparer: @escaping (Element, Element) -> Bool) -> SharedSequence<SharingStrategy, Element> {
        let source = self.asObservable()
            .distinctUntilChanged({ $0 }, comparer: comparer)
        return SharedSequence<SharingStrategy, Element>(source)
    }
    
    /**
    Returns an observable sequence that contains only distinct contiguous elements according to the keySelector and the comparer.
    
    - parameter keySelector: A function to compute the comparison key for each element.
    - parameter comparer: Equality comparer for computed key values.
    - returns: An observable sequence only containing the distinct contiguous elements, based on a computed key value and the comparer, from the source sequence.
    */
    public func distinctUntilChanged<K>(_ keySelector: @escaping (Element) -> K, comparer: @escaping (K, K) -> Bool) -> SharedSequence<SharingStrategy, Element> {
        let source = self.asObservable()
            .distinctUntilChanged(keySelector, comparer: comparer)
        return SharedSequence<SharingStrategy, Element>(source)
    }
}


// MARK: flatMap
extension SharedSequenceConvertibleType {
    
    /**
    Projects each element of an observable sequence to an observable sequence and merges the resulting observable sequences into one observable sequence.
    
    - parameter selector: A transform function to apply to each element.
    - returns: An observable sequence whose elements are the result of invoking the one-to-many transform function on each element of the input sequence.
    */
    public func flatMap<Sharing, Result>(_ selector: @escaping (Element) -> SharedSequence<Sharing, Result>) -> SharedSequence<Sharing, Result> {
        let source = self.asObservable()
            .flatMap(selector)
        
        return SharedSequence(source)
    }
}

// MARK: merge
extension SharedSequenceConvertibleType {
    /**
     Merges elements from all observable sequences from collection into a single observable sequence.

     - seealso: [merge operator on reactivex.io](http://reactivex.io/documentation/operators/merge.html)

     - parameter sources: Collection of observable sequences to merge.
     - returns: The observable sequence that merges the elements of the observable sequences.
     */
    public static func merge<Collection: Swift.Collection>(_ sources: Collection) -> SharedSequence<SharingStrategy, Element>
        where Collection.Element == SharedSequence<SharingStrategy, Element> {
        let source = Observable.merge(sources.map { $0.asObservable() })
        return SharedSequence<SharingStrategy, Element>(source)
    }

    /**
     Merges elements from all observable sequences from array into a single observable sequence.

     - seealso: [merge operator on reactivex.io](http://reactivex.io/documentation/operators/merge.html)

     - parameter sources: Array of observable sequences to merge.
     - returns: The observable sequence that merges the elements of the observable sequences.
     */
    public static func merge(_ sources: [SharedSequence<SharingStrategy, Element>]) -> SharedSequence<SharingStrategy, Element> {
        let source = Observable.merge(sources.map { $0.asObservable() })
        return SharedSequence<SharingStrategy, Element>(source)
    }

    /**
     Merges elements from all observable sequences into a single observable sequence.

     - seealso: [merge operator on reactivex.io](http://reactivex.io/documentation/operators/merge.html)

     - parameter sources: Collection of observable sequences to merge.
     - returns: The observable sequence that merges the elements of the observable sequences.
     */
    public static func merge(_ sources: SharedSequence<SharingStrategy, Element>...) -> SharedSequence<SharingStrategy, Element> {
        let source = Observable.merge(sources.map { $0.asObservable() })
        return SharedSequence<SharingStrategy, Element>(source)
    }
    
}

// MARK: merge
extension SharedSequenceConvertibleType where Element: SharedSequenceConvertibleType {
    /**
    Merges elements from all observable sequences in the given enumerable sequence into a single observable sequence.
    
    - returns: The observable sequence that merges the elements of the observable sequences.
    */
    public func merge() -> SharedSequence<Element.SharingStrategy, Element.Element> {
        let source = self.asObservable()
            .map { $0.asSharedSequence() }
            .merge()
        return SharedSequence<Element.SharingStrategy, Element.Element>(source)
    }
    
    /**
    Merges elements from all inner observable sequences into a single observable sequence, limiting the number of concurrent subscriptions to inner sequences.
    
    - parameter maxConcurrent: Maximum number of inner observable sequences being subscribed to concurrently.
    - returns: The observable sequence that merges the elements of the inner sequences.
    */
    public func merge(maxConcurrent: Int)
        -> SharedSequence<Element.SharingStrategy, Element.Element> {
        let source = self.asObservable()
            .map { $0.asSharedSequence() }
            .merge(maxConcurrent: maxConcurrent)
        return SharedSequence<Element.SharingStrategy, Element.Element>(source)
    }
}

// MARK: throttle
extension SharedSequenceConvertibleType {
    
    /**
     Returns an Observable that emits the first and the latest item emitted by the source Observable during sequential time windows of a specified duration.

     This operator makes sure that no two elements are emitted in less then dueTime.

     - seealso: [debounce operator on reactivex.io](http://reactivex.io/documentation/operators/debounce.html)

     - parameter dueTime: Throttling duration for each element.
     - parameter latest: Should latest element received in a dueTime wide time window since last element emission be emitted.
     - returns: The throttled sequence.
    */
    public func throttle(_ dueTime: RxTimeInterval, latest: Bool = true)
        -> SharedSequence<SharingStrategy, Element> {
        let source = self.asObservable()
            .throttle(dueTime, latest: latest, scheduler: SharingStrategy.scheduler)

        return SharedSequence(source)
    }

    /**
    Ignores elements from an observable sequence which are followed by another element within a specified relative time duration, using the specified scheduler to run throttling timers.
    
    - parameter dueTime: Throttling duration for each element.
    - returns: The throttled sequence.
    */
    public func debounce(_ dueTime: RxTimeInterval)
        -> SharedSequence<SharingStrategy, Element> {
        let source = self.asObservable()
            .debounce(dueTime, scheduler: SharingStrategy.scheduler)

        return SharedSequence(source)
    }
}

// MARK: scan
extension SharedSequenceConvertibleType {
    /**
    Applies an accumulator function over an observable sequence and returns each intermediate result. The specified seed value is used as the initial accumulator value.
    
    For aggregation behavior with no intermediate results, see `reduce`.
    
    - parameter seed: The initial accumulator value.
    - parameter accumulator: An accumulator function to be invoked on each element.
    - returns: An observable sequence containing the accumulated values.
    */
    public func scan<A>(_ seed: A, accumulator: @escaping (A, Element) -> A)
        -> SharedSequence<SharingStrategy, A> {
        let source = self.asObservable()
            .scan(seed, accumulator: accumulator)
        return SharedSequence<SharingStrategy, A>(source)
    }
}

// MARK: concat

extension SharedSequence {
    /**
     Concatenates all observable sequences in the given sequence, as long as the previous observable sequence terminated successfully.

     - returns: An observable sequence that contains the elements of each given sequence, in sequential order.
     */
    public static func concat<Sequence: Swift.Sequence>(_ sequence: Sequence) -> SharedSequence<SharingStrategy, Element>
        where Sequence.Element == SharedSequence<SharingStrategy, Element> {
            let source = Observable.concat(sequence.lazy.map { $0.asObservable() })
            return SharedSequence<SharingStrategy, Element>(source)
    }

    /**
     Concatenates all observable sequences in the given sequence, as long as the previous observable sequence terminated successfully.

     - returns: An observable sequence that contains the elements of each given sequence, in sequential order.
     */
    public static func concat<Collection: Swift.Collection>(_ collection: Collection) -> SharedSequence<SharingStrategy, Element>
        where Collection.Element == SharedSequence<SharingStrategy, Element> {
        let source = Observable.concat(collection.map { $0.asObservable() })
        return SharedSequence<SharingStrategy, Element>(source)
    }
}

// MARK: zip

extension SharedSequence {
    /**
     Merges the specified observable sequences into one observable sequence by using the selector function whenever all of the observable sequences have produced an element at a corresponding index.

     - parameter resultSelector: Function to invoke for each series of elements at corresponding indexes in the sources.
     - returns: An observable sequence containing the result of combining elements of the sources using the specified result selector function.
     */
    public static func zip<Collection: Swift.Collection, Result>(_ collection: Collection, resultSelector: @escaping ([Element]) throws -> Result) -> SharedSequence<SharingStrategy, Result>
        where Collection.Element == SharedSequence<SharingStrategy, Element> {
        let source = Observable.zip(collection.map { $0.asSharedSequence().asObservable() }, resultSelector: resultSelector)
        return SharedSequence<SharingStrategy, Result>(source)
    }

    /**
     Merges the specified observable sequences into one observable sequence all of the observable sequences have produced an element at a corresponding index.

     - returns: An observable sequence containing the result of combining elements of the sources.
     */
    public static func zip<Collection: Swift.Collection>(_ collection: Collection) -> SharedSequence<SharingStrategy, [Element]>
        where Collection.Element == SharedSequence<SharingStrategy, Element> {
            let source = Observable.zip(collection.map { $0.asSharedSequence().asObservable() })
            return SharedSequence<SharingStrategy, [Element]>(source)
    }
}

// MARK: combineLatest

extension SharedSequence {
    /**
     Merges the specified observable sequences into one observable sequence by using the selector function whenever any of the observable sequences produces an element.

     - parameter resultSelector: Function to invoke whenever any of the sources produces an element.
     - returns: An observable sequence containing the result of combining elements of the sources using the specified result selector function.
     */
    public static func combineLatest<Collection: Swift.Collection, Result>(_ collection: Collection, resultSelector: @escaping ([Element]) throws -> Result) -> SharedSequence<SharingStrategy, Result>
        where Collection.Element == SharedSequence<SharingStrategy, Element> {
        let source = Observable.combineLatest(collection.map { $0.asObservable() }, resultSelector: resultSelector)
        return SharedSequence<SharingStrategy, Result>(source)
    }

    /**
     Merges the specified observable sequences into one observable sequence whenever any of the observable sequences produces an element.

     - returns: An observable sequence containing the result of combining elements of the sources.
     */
    public static func combineLatest<Collection: Swift.Collection>(_ collection: Collection) -> SharedSequence<SharingStrategy, [Element]>
        where Collection.Element == SharedSequence<SharingStrategy, Element> {
        let source = Observable.combineLatest(collection.map { $0.asObservable() })
        return SharedSequence<SharingStrategy, [Element]>(source)
    }
}

// MARK: - withUnretained
extension SharedSequenceConvertibleType where SharingStrategy == SignalSharingStrategy {
    /**
     Provides an unretained, safe to use (i.e. not implicitly unwrapped), reference to an object along with the events emitted by the sequence.
     
     In the case the provided object cannot be retained successfully, the seqeunce will complete.
     
     - note: Be careful when using this operator in a sequence that has a buffer or replay, for example `share(replay: 1)`, as the sharing buffer will also include the provided object, which could potentially cause a retain cycle.
     
     - parameter obj: The object to provide an unretained reference on.
     - parameter resultSelector: A function to combine the unretained referenced on `obj` and the value of the observable sequence.
     - returns: An observable sequence that contains the result of `resultSelector` being called with an unretained reference on `obj` and the values of the original sequence.
     */
    public func withUnretained<Object: AnyObject, Out>(
        _ obj: Object,
        resultSelector: @escaping (Object, Element) -> Out
    ) -> SharedSequence<SharingStrategy, Out> {
        SharedSequence(self.asObservable().withUnretained(obj, resultSelector: resultSelector))
    }

    /**
     Provides an unretained, safe to use (i.e. not implicitly unwrapped), reference to an object along with the events emitted by the sequence.
     
     In the case the provided object cannot be retained successfully, the seqeunce will complete.
     
     - note: Be careful when using this operator in a sequence that has a buffer or replay, for example `share(replay: 1)`, as the sharing buffer will also include the provided object, which could potentially cause a retain cycle.
     
     - parameter obj: The object to provide an unretained reference on.
     - returns: An observable sequence of tuples that contains both an unretained reference on `obj` and the values of the original sequence.
     */
    public func withUnretained<Object: AnyObject>(_ obj: Object) -> SharedSequence<SharingStrategy, (Object, Element)> {
        withUnretained(obj) { ($0, $1) }
    }
}

extension SharedSequenceConvertibleType where SharingStrategy == DriverSharingStrategy {
    @available(*, message: "withUnretained has been deprecated for Driver. Consider using `drive(with:onNext:onCompleted:onDisposed:)`, instead", unavailable)
    public func withUnretained<Object: AnyObject, Out>(
        _ obj: Object,
        resultSelector: @escaping (Object, Element) -> Out
    ) -> SharedSequence<SharingStrategy, Out> {
        SharedSequence(self.asObservable().withUnretained(obj, resultSelector: resultSelector))
    }
    
    @available(*, message: "withUnretained has been deprecated for Driver. Consider using `drive(with:onNext:onCompleted:onDisposed:)`, instead", unavailable)
    public func withUnretained<Object: AnyObject>(_ obj: Object) -> SharedSequence<SharingStrategy, (Object, Element)> {
        SharedSequence(self.asObservable().withUnretained(obj) { ($0, $1) })
    }
}

// MARK: withLatestFrom
extension SharedSequenceConvertibleType {

    /**
    Merges two observable sequences into one observable sequence by combining each element from self with the latest element from the second source, if any.

    - parameter second: Second observable source.
    - parameter resultSelector: Function to invoke for each element from the self combined with the latest element from the second source, if any.
    - returns: An observable sequence containing the result of combining each element of the self  with the latest element from the second source, if any, using the specified result selector function.
    */
    public func withLatestFrom<SecondO: SharedSequenceConvertibleType, ResultType>(_ second: SecondO, resultSelector: @escaping (Element, SecondO.Element) -> ResultType) -> SharedSequence<SharingStrategy, ResultType> where SecondO.SharingStrategy == SharingStrategy {
        let source = self.asObservable()
            .withLatestFrom(second.asSharedSequence(), resultSelector: resultSelector)

        return SharedSequence<SharingStrategy, ResultType>(source)
    }

    /**
    Merges two observable sequences into one observable sequence by using latest element from the second sequence every time when `self` emits an element.

    - parameter second: Second observable source.
    - returns: An observable sequence containing the result of combining each element of the self  with the latest element from the second source, if any, using the specified result selector function.
    */
    public func withLatestFrom<SecondO: SharedSequenceConvertibleType>(_ second: SecondO) -> SharedSequence<SharingStrategy, SecondO.Element> {
        let source = self.asObservable()
            .withLatestFrom(second.asSharedSequence())

        return SharedSequence<SharingStrategy, SecondO.Element>(source)
    }
}

// MARK: skip
extension SharedSequenceConvertibleType {

    /**
     Bypasses a specified number of elements in an observable sequence and then returns the remaining elements.

     - seealso: [skip operator on reactivex.io](http://reactivex.io/documentation/operators/skip.html)

     - parameter count: The number of elements to skip before returning the remaining elements.
     - returns: An observable sequence that contains the elements that occur after the specified index in the input sequence.
     */
    public func skip(_ count: Int)
        -> SharedSequence<SharingStrategy, Element> {
        let source = self.asObservable()
            .skip(count)
        return SharedSequence(source)
    }
}

// MARK: startWith
extension SharedSequenceConvertibleType {
    
    /**
    Prepends a value to an observable sequence.

    - seealso: [startWith operator on reactivex.io](http://reactivex.io/documentation/operators/startwith.html)
    
    - parameter element: Element to prepend to the specified sequence.
    - returns: The source sequence prepended with the specified values.
    */
    public func startWith(_ element: Element)
        -> SharedSequence<SharingStrategy, Element> {
        let source = self.asObservable()
                .startWith(element)

        return SharedSequence(source)
    }
}

// MARK: delay
extension SharedSequenceConvertibleType {

    /**
     Returns an observable sequence by the source observable sequence shifted forward in time by a specified delay. Error events from the source observable sequence are not delayed.

     - seealso: [delay operator on reactivex.io](http://reactivex.io/documentation/operators/delay.html)

     - parameter dueTime: Relative time shift of the source by.
     - parameter scheduler: Scheduler to run the subscription delay timer on.
     - returns: the source Observable shifted in time by the specified delay.
     */
    public func delay(_ dueTime: RxTimeInterval)
        -> SharedSequence<SharingStrategy, Element> {
        let source = self.asObservable()
            .delay(dueTime, scheduler: SharingStrategy.scheduler)

        return SharedSequence(source)
    }
}
