//
//  Infallible+Operators.swift
//  RxSwift
//
//  Created by Shai Mishali on 27/08/2020.
//  Copyright © 2020 Krunoslav Zaher. All rights reserved.
//

// MARK: - Static allocation
extension InfallibleType {
    /**
     Returns an infallible sequence that contains a single element.

     - seealso: [just operator on reactivex.io](http://reactivex.io/documentation/operators/just.html)

     - parameter element: Single element in the resulting infallible sequence.

     - returns: An infallible sequence containing the single specified element.
     */
    public static func just(_ element: Element) -> Infallible<Element> {
        Infallible(.just(element))
    }

    /**
     Returns an infallible sequence that contains a single element.

     - seealso: [just operator on reactivex.io](http://reactivex.io/documentation/operators/just.html)

     - parameter element: Single element in the resulting infallible sequence.
     - parameter scheduler: Scheduler to send the single element on.
     - returns: An infallible sequence containing the single specified element.
     */
    public static func just(_ element: Element, scheduler: ImmediateSchedulerType) -> Infallible<Element> {
        Infallible(.just(element, scheduler: scheduler))
    }

    /**
     Returns a non-terminating infallible sequence, which can be used to denote an infinite duration.

     - seealso: [never operator on reactivex.io](http://reactivex.io/documentation/operators/empty-never-throw.html)

     - returns: An infallible sequence whose observers will never get called.
     */
    public static func never() -> Infallible<Element> {
        Infallible(.never())
    }

    /**
     Returns an empty infallible sequence, using the specified scheduler to send out the single `Completed` message.

     - seealso: [empty operator on reactivex.io](http://reactivex.io/documentation/operators/empty-never-throw.html)

     - returns: An infallible sequence with no elements.
     */
    public static func empty() -> Infallible<Element> {
        Infallible(.empty())
    }

    /**
     Returns an infallible sequence that invokes the specified factory function whenever a new observer subscribes.

     - seealso: [defer operator on reactivex.io](http://reactivex.io/documentation/operators/defer.html)

     - parameter observableFactory: Observable factory function to invoke for each observer that subscribes to the resulting sequence.
     - returns: An observable sequence whose observers trigger an invocation of the given observable factory function.
     */
    public static func deferred(_ observableFactory: @escaping () throws -> Infallible<Element>)
        -> Infallible<Element> {
        Infallible(.deferred { try observableFactory().asObservable() })
    }
}

// MARK: From & Of

extension Infallible {
    /**
     This method creates a new Infallible instance with a variable number of elements.

     - seealso: [from operator on reactivex.io](http://reactivex.io/documentation/operators/from.html)

     - parameter elements: Elements to generate.
     - parameter scheduler: Scheduler to send elements on. If `nil`, elements are sent immediately on subscription.
     - returns: The Infallible sequence whose elements are pulled from the given arguments.
     */
    public static func of(_ elements: Element ..., scheduler: ImmediateSchedulerType = CurrentThreadScheduler.instance) -> Infallible<Element> {
        Infallible(Observable.from(elements, scheduler: scheduler))
    }
}

extension Infallible {
    /**
     Converts an array to an Infallible sequence.

     - seealso: [from operator on reactivex.io](http://reactivex.io/documentation/operators/from.html)

     - returns: The Infallible sequence whose elements are pulled from the given enumerable sequence.
     */
    public static func from(_ array: [Element], scheduler: ImmediateSchedulerType = CurrentThreadScheduler.instance) -> Infallible<Element> {
        Infallible(Observable.from(array, scheduler: scheduler))
    }

    /**
     Converts a sequence to an Infallible sequence.

     - seealso: [from operator on reactivex.io](http://reactivex.io/documentation/operators/from.html)

     - returns: The Infallible sequence whose elements are pulled from the given enumerable sequence.
     */
    public static func from<Sequence: Swift.Sequence>(_ sequence: Sequence, scheduler: ImmediateSchedulerType = CurrentThreadScheduler.instance) -> Infallible<Element> where Sequence.Element == Element {
        Infallible(Observable.from(sequence, scheduler: scheduler))
    }
}

// MARK: - Filter
extension InfallibleType {
    /**
     Filters the elements of an observable sequence based on a predicate.

     - seealso: [filter operator on reactivex.io](http://reactivex.io/documentation/operators/filter.html)

     - parameter predicate: A function to test each source element for a condition.
     - returns: An observable sequence that contains elements from the input sequence that satisfy the condition.
     */
    public func filter(_ predicate: @escaping (Element) -> Bool)
        -> Infallible<Element> {
        Infallible(asObservable().filter(predicate))
    }
}

// MARK: - Map
extension InfallibleType {
    /**
     Projects each element of an observable sequence into a new form.

     - seealso: [map operator on reactivex.io](http://reactivex.io/documentation/operators/map.html)

     - parameter transform: A transform function to apply to each source element.
     - returns: An observable sequence whose elements are the result of invoking the transform function on each element of source.

     */
    public func map<Result>(_ transform: @escaping (Element) -> Result)
        -> Infallible<Result> {
        Infallible(asObservable().map(transform))
    }

    /**
     Projects each element of an observable sequence into an optional form and filters all optional results.

     - parameter transform: A transform function to apply to each source element and which returns an element or nil.
     - returns: An observable sequence whose elements are the result of filtering the transform function for each element of the source.

     */
    public func compactMap<Result>(_ transform: @escaping (Element) -> Result?)
        -> Infallible<Result> {
        Infallible(asObservable().compactMap(transform))
    }
}

// MARK: - Distinct

extension InfallibleType where Element: Comparable {
    /**
     Returns an observable sequence that contains only distinct contiguous elements according to equality operator.

     - seealso: [distinct operator on reactivex.io](http://reactivex.io/documentation/operators/distinct.html)

     - returns: An observable sequence only containing the distinct contiguous elements, based on equality operator, from the source sequence.
     */
    public func distinctUntilChanged()
        -> Infallible<Element> {
        Infallible(asObservable().distinctUntilChanged())
    }
}

extension InfallibleType {
    /**
     Returns an observable sequence that contains only distinct contiguous elements according to the `keySelector`.

     - seealso: [distinct operator on reactivex.io](http://reactivex.io/documentation/operators/distinct.html)

     - parameter keySelector: A function to compute the comparison key for each element.
     - returns: An observable sequence only containing the distinct contiguous elements, based on a computed key value, from the source sequence.
     */
    public func distinctUntilChanged<Key: Equatable>(_ keySelector: @escaping (Element) throws -> Key)
        -> Infallible<Element> {
        Infallible(self.asObservable().distinctUntilChanged(keySelector, comparer: { $0 == $1 }))
    }

    /**
     Returns an observable sequence that contains only distinct contiguous elements according to the `comparer`.

     - seealso: [distinct operator on reactivex.io](http://reactivex.io/documentation/operators/distinct.html)

     - parameter comparer: Equality comparer for computed key values.
     - returns: An observable sequence only containing the distinct contiguous elements, based on `comparer`, from the source sequence.
     */
    public func distinctUntilChanged(_ comparer: @escaping (Element, Element) throws -> Bool)
        -> Infallible<Element> {
        Infallible(self.asObservable().distinctUntilChanged({ $0 }, comparer: comparer))
    }

    /**
     Returns an observable sequence that contains only distinct contiguous elements according to the keySelector and the comparer.

     - seealso: [distinct operator on reactivex.io](http://reactivex.io/documentation/operators/distinct.html)

     - parameter keySelector: A function to compute the comparison key for each element.
     - parameter comparer: Equality comparer for computed key values.
     - returns: An observable sequence only containing the distinct contiguous elements, based on a computed key value and the comparer, from the source sequence.
     */
    public func distinctUntilChanged<K>(_ keySelector: @escaping (Element) throws -> K, comparer: @escaping (K, K) throws -> Bool)
        -> Infallible<Element> {
        Infallible(asObservable().distinctUntilChanged(keySelector, comparer: comparer))
    }

    /**
    Returns an observable sequence that contains only contiguous elements with distinct values in the provided key path on each object.

    - seealso: [distinct operator on reactivex.io](http://reactivex.io/documentation/operators/distinct.html)

    - returns: An observable sequence only containing the distinct contiguous elements, based on equality operator on the provided key path
    */
    public func distinctUntilChanged<Property: Equatable>(at keyPath: KeyPath<Element, Property>) ->
        Infallible<Element> {
        Infallible(asObservable().distinctUntilChanged { $0[keyPath: keyPath] == $1[keyPath: keyPath] })
    }
}

// MARK: - Throttle
extension InfallibleType {
    /**
     Ignores elements from an observable sequence which are followed by another element within a specified relative time duration, using the specified scheduler to run throttling timers.

     - seealso: [debounce operator on reactivex.io](http://reactivex.io/documentation/operators/debounce.html)

     - parameter dueTime: Throttling duration for each element.
     - parameter scheduler: Scheduler to run the throttle timers on.
     - returns: The throttled sequence.
     */
    public func debounce(_ dueTime: RxTimeInterval, scheduler: SchedulerType)
        -> Infallible<Element> {
        Infallible(asObservable().debounce(dueTime, scheduler: scheduler))
    }

    /**
     Returns an Observable that emits the first and the latest item emitted by the source Observable during sequential time windows of a specified duration.

     This operator makes sure that no two elements are emitted in less then dueTime.

     - seealso: [debounce operator on reactivex.io](http://reactivex.io/documentation/operators/debounce.html)

     - parameter dueTime: Throttling duration for each element.
     - parameter latest: Should latest element received in a dueTime wide time window since last element emission be emitted.
     - parameter scheduler: Scheduler to run the throttle timers on.
     - returns: The throttled sequence.
     */
    public func throttle(_ dueTime: RxTimeInterval, latest: Bool = true, scheduler: SchedulerType)
        -> Infallible<Element> {
        Infallible(asObservable().throttle(dueTime, latest: latest, scheduler: scheduler))
    }
}

// MARK: - FlatMap
extension InfallibleType {
    /**
     Projects each element of an observable sequence to an observable sequence and merges the resulting observable sequences into one observable sequence.

     - seealso: [flatMap operator on reactivex.io](http://reactivex.io/documentation/operators/flatmap.html)

     - parameter selector: A transform function to apply to each element.
     - returns: An observable sequence whose elements are the result of invoking the one-to-many transform function on each element of the input sequence.
     */
    public func flatMap<Source: ObservableConvertibleType>(_ selector: @escaping (Element) -> Source)
        -> Infallible<Source.Element> {
        Infallible(asObservable().flatMap(selector))
    }

    /**
     Projects each element of an observable sequence into a new sequence of observable sequences and then
     transforms an observable sequence of observable sequences into an observable sequence producing values only from the most recent observable sequence.

     It is a combination of `map` + `switchLatest` operator

     - seealso: [flatMapLatest operator on reactivex.io](http://reactivex.io/documentation/operators/flatmap.html)

     - parameter selector: A transform function to apply to each element.
     - returns: An observable sequence whose elements are the result of invoking the transform function on each element of source producing an
     Observable of Observable sequences and that at any point in time produces the elements of the most recent inner observable sequence that has been received.
     */
    public func flatMapLatest<Source: ObservableConvertibleType>(_ selector: @escaping (Element) -> Source)
        -> Infallible<Source.Element> {
        Infallible(asObservable().flatMapLatest(selector))
    }

    /**
     Projects each element of an observable sequence to an observable sequence and merges the resulting observable sequences into one observable sequence.
     If element is received while there is some projected observable sequence being merged it will simply be ignored.

     - seealso: [flatMapFirst operator on reactivex.io](http://reactivex.io/documentation/operators/flatmap.html)

     - parameter selector: A transform function to apply to element that was observed while no observable is executing in parallel.
     - returns: An observable sequence whose elements are the result of invoking the one-to-many transform function on each element of the input sequence that was received while no other sequence was being calculated.
     */
    public func flatMapFirst<Source: ObservableConvertibleType>(_ selector: @escaping (Element) -> Source)
        -> Infallible<Source.Element> {
        Infallible(asObservable().flatMapFirst(selector))
    }
}

// MARK: - Concat
extension InfallibleType {
    /**
     Concatenates the second observable sequence to `self` upon successful termination of `self`.

     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)

     - parameter second: Second observable sequence.
     - returns: An observable sequence that contains the elements of `self`, followed by those of the second sequence.
     */
    public func concat<Source: ObservableConvertibleType>(_ second: Source) -> Infallible<Element> where Source.Element == Element {
        Infallible(Observable.concat([self.asObservable(), second.asObservable()]))
    }

    /**
     Concatenates all observable sequences in the given sequence, as long as the previous observable sequence terminated successfully.

     This operator has tail recursive optimizations that will prevent stack overflow.

     Optimizations will be performed in cases equivalent to following:

     [1, [2, [3, .....].concat()].concat].concat()

     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)

     - returns: An observable sequence that contains the elements of each given sequence, in sequential order.
     */
    public static func concat<Sequence: Swift.Sequence>(_ sequence: Sequence) -> Infallible<Element>
        where Sequence.Element == Infallible<Element> {
        Infallible(Observable.concat(sequence.map { $0.asObservable() }))
    }

    /**
     Concatenates all observable sequences in the given collection, as long as the previous observable sequence terminated successfully.

     This operator has tail recursive optimizations that will prevent stack overflow.

     Optimizations will be performed in cases equivalent to following:

     [1, [2, [3, .....].concat()].concat].concat()

     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)

     - returns: An observable sequence that contains the elements of each given sequence, in sequential order.
     */
    public static func concat<Collection: Swift.Collection>(_ collection: Collection) -> Infallible<Element>
        where Collection.Element == Infallible<Element> {
        Infallible(Observable.concat(collection.map { $0.asObservable() }))
    }

    /**
     Concatenates all observable sequences in the given collection, as long as the previous observable sequence terminated successfully.

     This operator has tail recursive optimizations that will prevent stack overflow.

     Optimizations will be performed in cases equivalent to following:

     [1, [2, [3, .....].concat()].concat].concat()

     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)

     - returns: An observable sequence that contains the elements of each given sequence, in sequential order.
     */
    public static func concat(_ sources: Infallible<Element> ...) -> Infallible<Element> {
        Infallible(Observable.concat(sources.map { $0.asObservable() }))
    }

    /**
     Projects each element of an observable sequence to an observable sequence and concatenates the resulting observable sequences into one observable sequence.

     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)

     - returns: An observable sequence that contains the elements of each observed inner sequence, in sequential order.
     */
    public func concatMap<Source: ObservableConvertibleType>(_ selector: @escaping (Element) -> Source)
        -> Infallible<Source.Element> {
        Infallible(asObservable().concatMap(selector))
    }
}

// MARK: - Merge
extension InfallibleType {
    /**
     Merges elements from all observable sequences from collection into a single observable sequence.

     - seealso: [merge operator on reactivex.io](http://reactivex.io/documentation/operators/merge.html)

     - parameter sources: Collection of observable sequences to merge.
     - returns: The observable sequence that merges the elements of the observable sequences.
     */
    public static func merge<Collection: Swift.Collection>(_ sources: Collection) -> Infallible<Element> where Collection.Element == Infallible<Element> {
        Infallible(Observable.concat(sources.map { $0.asObservable() }))
    }

    /**
     Merges elements from all infallible sequences from array into a single infallible sequence.

     - seealso: [merge operator on reactivex.io](http://reactivex.io/documentation/operators/merge.html)

     - parameter sources: Array of infallible sequences to merge.
     - returns: The infallible sequence that merges the elements of the infallible sequences.
     */
    public static func merge(_ sources: [Infallible<Element>]) -> Infallible<Element> {
        Infallible(Observable.merge(sources.map { $0.asObservable() }))
    }

    /**
     Merges elements from all infallible sequences into a single infallible sequence.

     - seealso: [merge operator on reactivex.io](http://reactivex.io/documentation/operators/merge.html)

     - parameter sources: Collection of infallible sequences to merge.
     - returns: The infallible sequence that merges the elements of the infallible sequences.
     */
    public static func merge(_ sources: Infallible<Element>...) -> Infallible<Element> {
        Infallible(Observable.merge(sources.map { $0.asObservable() }))
    }
}

// MARK: - Do

extension Infallible {
    /**
     Invokes an action for each event in the infallible sequence, and propagates all observer messages through the result sequence.

     - seealso: [do operator on reactivex.io](http://reactivex.io/documentation/operators/do.html)

     - parameter onNext: Action to invoke for each element in the observable sequence.
     - parameter afterNext: Action to invoke for each element after the observable has passed an onNext event along to its downstream.
     - parameter onCompleted: Action to invoke upon graceful termination of the observable sequence.
     - parameter afterCompleted: Action to invoke after graceful termination of the observable sequence.
     - parameter onSubscribe: Action to invoke before subscribing to source observable sequence.
     - parameter onSubscribed: Action to invoke after subscribing to source observable sequence.
     - parameter onDispose: Action to invoke after subscription to source observable has been disposed for any reason. It can be either because sequence terminates for some reason or observer subscription being disposed.
     - returns: The source sequence with the side-effecting behavior applied.
     */
    public func `do`(onNext: ((Element) throws -> Void)? = nil, afterNext: ((Element) throws -> Void)? = nil, onCompleted: (() throws -> Void)? = nil, afterCompleted: (() throws -> Void)? = nil, onSubscribe: (() -> Void)? = nil, onSubscribed: (() -> Void)? = nil, onDispose: (() -> Void)? = nil) -> Infallible<Element> {
        Infallible(asObservable().do(onNext: onNext, afterNext: afterNext, onCompleted: onCompleted, afterCompleted: afterCompleted, onSubscribe: onSubscribe, onSubscribed: onSubscribed, onDispose: onDispose))
    }
}

// MARK: - Scan
extension InfallibleType {
    /**
     Applies an accumulator function over an observable sequence and returns each intermediate result. The specified seed value is used as the initial accumulator value.

     For aggregation behavior with no intermediate results, see `reduce`.

     - seealso: [scan operator on reactivex.io](http://reactivex.io/documentation/operators/scan.html)

     - parameter seed: The initial accumulator value.
     - parameter accumulator: An accumulator function to be invoked on each element.
     - returns: An observable sequence containing the accumulated values.
     */
    public func scan<Seed>(into seed: Seed, accumulator: @escaping (inout Seed, Element) -> Void)
        -> Infallible<Seed> {
        Infallible(asObservable().scan(into: seed, accumulator: accumulator))
    }

    /**
     Applies an accumulator function over an observable sequence and returns each intermediate result. The specified seed value is used as the initial accumulator value.

     For aggregation behavior with no intermediate results, see `reduce`.

     - seealso: [scan operator on reactivex.io](http://reactivex.io/documentation/operators/scan.html)

     - parameter seed: The initial accumulator value.
     - parameter accumulator: An accumulator function to be invoked on each element.
     - returns: An observable sequence containing the accumulated values.
     */
    public func scan<Seed>(_ seed: Seed, accumulator: @escaping (Seed, Element) -> Seed)
        -> Infallible<Seed> {
        Infallible(asObservable().scan(seed, accumulator: accumulator))
    }
}

// MARK: - Start with

extension InfallibleType {
    /**
    Prepends a value to an observable sequence.

    - seealso: [startWith operator on reactivex.io](http://reactivex.io/documentation/operators/startwith.html)

    - parameter element: Element to prepend to the specified sequence.
    - returns: The source sequence prepended with the specified values.
    */
    public func startWith(_ element: Element) -> Infallible<Element> {
        Infallible(asObservable().startWith(element))
    }
}



// MARK: - Take and Skip {
extension InfallibleType {
    /**
     Returns the elements from the source observable sequence until the other observable sequence produces an element.

     - seealso: [takeUntil operator on reactivex.io](http://reactivex.io/documentation/operators/takeuntil.html)

     - parameter other: Observable sequence that terminates propagation of elements of the source sequence.
     - returns: An observable sequence containing the elements of the source sequence up to the point the other sequence interrupted further propagation.
     */
    public func take<Source: InfallibleType>(until other: Source)
        -> Infallible<Element> {
        Infallible(asObservable().take(until: other.asObservable()))
    }

    /**
     Returns the elements from the source observable sequence until the other observable sequence produces an element.

     - seealso: [takeUntil operator on reactivex.io](http://reactivex.io/documentation/operators/takeuntil.html)

     - parameter other: Observable sequence that terminates propagation of elements of the source sequence.
     - returns: An observable sequence containing the elements of the source sequence up to the point the other sequence interrupted further propagation.
     */
    public func take<Source: ObservableType>(until other: Source)
        -> Infallible<Element> {
        Infallible(asObservable().take(until: other))
    }

    /**
     Returns elements from an observable sequence until the specified condition is true.

     - seealso: [takeUntil operator on reactivex.io](http://reactivex.io/documentation/operators/takeuntil.html)

     - parameter predicate: A function to test each element for a condition.
     - parameter behavior: Whether or not to include the last element matching the predicate. Defaults to `exclusive`.

     - returns: An observable sequence that contains the elements from the input sequence that occur before the element at which the test passes.
     */
    public func take(until predicate: @escaping (Element) throws -> Bool,
                     behavior: TakeBehavior = .exclusive)
        -> Infallible<Element> {
        Infallible(asObservable().take(until: predicate, behavior: behavior))
    }

    /**
     Returns elements from an observable sequence as long as a specified condition is true.

     - seealso: [takeWhile operator on reactivex.io](http://reactivex.io/documentation/operators/takewhile.html)

     - parameter predicate: A function to test each element for a condition.
     - returns: An observable sequence that contains the elements from the input sequence that occur before the element at which the test no longer passes.
     */
    public func take(while predicate: @escaping (Element) throws -> Bool,
                     behavior: TakeBehavior = .exclusive)
        -> Infallible<Element> {
        Infallible(asObservable().take(while: predicate, behavior: behavior))
    }

    /**
     Returns a specified number of contiguous elements from the start of an observable sequence.

     - seealso: [take operator on reactivex.io](http://reactivex.io/documentation/operators/take.html)

     - parameter count: The number of elements to return.
     - returns: An observable sequence that contains the specified number of elements from the start of the input sequence.
     */
    public func take(_ count: Int) -> Infallible<Element> {
        Infallible(asObservable().take(count))
    }

    /**
     Takes elements for the specified duration from the start of the infallible source sequence, using the specified scheduler to run timers.

     - seealso: [take operator on reactivex.io](http://reactivex.io/documentation/operators/take.html)

     - parameter duration: Duration for taking elements from the start of the sequence.
     - parameter scheduler: Scheduler to run the timer on.
     - returns: An infallible sequence with the elements taken during the specified duration from the start of the source sequence.
     */
    public func take(for duration: RxTimeInterval, scheduler: SchedulerType)
        -> Infallible<Element> {
        Infallible(asObservable().take(for: duration, scheduler: scheduler))
    }

    /**
     Bypasses elements in an infallible sequence as long as a specified condition is true and then returns the remaining elements.

     - seealso: [skipWhile operator on reactivex.io](http://reactivex.io/documentation/operators/skipwhile.html)

     - parameter predicate: A function to test each element for a condition.
     - returns: An infallible sequence that contains the elements from the input sequence starting at the first element in the linear series that does not pass the test specified by predicate.
     */
    public func skip(while predicate: @escaping (Element) throws -> Bool) -> Infallible<Element> {
        Infallible(asObservable().skip(while: predicate))
    }

    /**
     Returns the elements from the source infallible sequence that are emitted after the other infallible sequence produces an element.

     - seealso: [skipUntil operator on reactivex.io](http://reactivex.io/documentation/operators/skipuntil.html)

     - parameter other: Infallible sequence that starts propagation of elements of the source sequence.
     - returns: An infallible sequence containing the elements of the source sequence that are emitted after the other sequence emits an item.
     */
    public func skip<Source: ObservableType>(until other: Source)
        -> Infallible<Element> {
        Infallible(asObservable().skip(until: other))
    }
}

// MARK: - Share
extension InfallibleType {
    /**
     Returns an observable sequence that **shares a single subscription to the underlying sequence**, and immediately upon subscription replays  elements in buffer.

     This operator is equivalent to:
     * `.whileConnected`
     ```
     // Each connection will have it's own subject instance to store replay events.
     // Connections will be isolated from each another.
     source.multicast(makeSubject: { Replay.create(bufferSize: replay) }).refCount()
     ```
     * `.forever`
     ```
     // One subject will store replay events for all connections to source.
     // Connections won't be isolated from each another.
     source.multicast(Replay.create(bufferSize: replay)).refCount()
     ```

     It uses optimized versions of the operators for most common operations.

     - parameter replay: Maximum element count of the replay buffer.
     - parameter scope: Lifetime scope of sharing subject. For more information see `SubjectLifetimeScope` enum.

     - seealso: [shareReplay operator on reactivex.io](http://reactivex.io/documentation/operators/replay.html)

     - returns: An observable sequence that contains the elements of a sequence produced by multicasting the source sequence.
     */
    public func share(replay: Int = 0, scope: SubjectLifetimeScope = .whileConnected)
        -> Infallible<Element> {
        Infallible(asObservable().share(replay: replay, scope: scope))
    }
}

// MARK: - withUnretained
extension InfallibleType {
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
    ) -> Infallible<Out> {
        Infallible(self.asObservable().withUnretained(obj, resultSelector: resultSelector))
    }
    
    /**
     Provides an unretained, safe to use (i.e. not implicitly unwrapped), reference to an object along with the events emitted by the sequence.
     
     In the case the provided object cannot be retained successfully, the seqeunce will complete.
     
     - note: Be careful when using this operator in a sequence that has a buffer or replay, for example `share(replay: 1)`, as the sharing buffer will also include the provided object, which could potentially cause a retain cycle.
     
     - parameter obj: The object to provide an unretained reference on.
     - returns: An observable sequence of tuples that contains both an unretained reference on `obj` and the values of the original sequence.
     */
    public func withUnretained<Object: AnyObject>(_ obj: Object) -> Infallible<(Object, Element)> {
        withUnretained(obj) { ($0, $1) }
    }
}

extension InfallibleType {
    // MARK: - withLatestFrom
    /**
     Merges two observable sequences into one observable sequence by combining each element from self with the latest element from the second source, if any.

     - seealso: [combineLatest operator on reactivex.io](http://reactivex.io/documentation/operators/combinelatest.html)
     - note: Elements emitted by self before the second source has emitted any values will be omitted.

     - parameter second: Second observable source.
     - parameter resultSelector: Function to invoke for each element from the self combined with the latest element from the second source, if any.
     - returns: An observable sequence containing the result of combining each element of the self  with the latest element from the second source, if any, using the specified result selector function.
     */
    public func withLatestFrom<Source: InfallibleType, ResultType>(_ second: Source, resultSelector: @escaping (Element, Source.Element) throws -> ResultType) -> Infallible<ResultType> {
        Infallible(self.asObservable().withLatestFrom(second.asObservable(), resultSelector: resultSelector))
    }

    /**
     Merges two observable sequences into one observable sequence by using latest element from the second sequence every time when `self` emits an element.

     - seealso: [combineLatest operator on reactivex.io](http://reactivex.io/documentation/operators/combinelatest.html)
     - note: Elements emitted by self before the second source has emitted any values will be omitted.

     - parameter second: Second observable source.
     - returns: An observable sequence containing the result of combining each element of the self  with the latest element from the second source, if any, using the specified result selector function.
     */
    public func withLatestFrom<Source: InfallibleType>(_ second: Source) -> Infallible<Source.Element> {
        withLatestFrom(second) { $1 }
    }
}
