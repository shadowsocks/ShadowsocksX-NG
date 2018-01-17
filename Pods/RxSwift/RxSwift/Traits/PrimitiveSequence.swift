//
//  PrimitiveSequence.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/5/17.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

/// Observable sequences containing 0 or 1 element.
public struct PrimitiveSequence<Trait, Element> {
    fileprivate let source: Observable<Element>

    init(raw: Observable<Element>) {
        self.source = raw
    }
}

/// Sequence containing exactly 1 element
public enum SingleTrait { }
/// Represents a push style sequence containing 1 element.
public typealias Single<Element> = PrimitiveSequence<SingleTrait, Element>

/// Sequence containing 0 or 1 elements
public enum MaybeTrait { }
/// Represents a push style sequence containing 0 or 1 element.
public typealias Maybe<Element> = PrimitiveSequence<MaybeTrait, Element>

/// Sequence containing 0 elements
public enum CompletableTrait { }
/// Represents a push style sequence containing 0 elements.
public typealias Completable = PrimitiveSequence<CompletableTrait, Swift.Never>

/// Observable sequences containing 0 or 1 element
public protocol PrimitiveSequenceType {
    /// Additional constraints
    associatedtype TraitType
    /// Sequence element type
    associatedtype ElementType

    // Converts `self` to primitive sequence.
    ///
    /// - returns: Observable sequence that represents `self`.
    var primitiveSequence: PrimitiveSequence<TraitType, ElementType> { get }
}

extension PrimitiveSequence: PrimitiveSequenceType {
    /// Additional constraints
    public typealias TraitType = Trait
    /// Sequence element type
    public typealias ElementType = Element

    // Converts `self` to primitive sequence.
    ///
    /// - returns: Observable sequence that represents `self`.
    public var primitiveSequence: PrimitiveSequence<TraitType, ElementType> {
        return self
    }
}

extension PrimitiveSequence: ObservableConvertibleType {
    /// Type of elements in sequence.
    public typealias E = Element

    /// Converts `self` to `Observable` sequence.
    ///
    /// - returns: Observable sequence that represents `self`.
    public func asObservable() -> Observable<E> {
        return source
    }
}

// <Single>

public enum SingleEvent<Element> {
    /// One and only sequence element is produced. (underlying observable sequence emits: `.next(Element)`, `.completed`)
    case success(Element)

    /// Sequence terminated with an error. (underlying observable sequence emits: `.error(Error)`)
    case error(Swift.Error)
}

extension PrimitiveSequenceType where TraitType == SingleTrait {
    public typealias SingleObserver = (SingleEvent<ElementType>) -> ()

    /**
     Creates an observable sequence from a specified subscribe method implementation.

     - seealso: [create operator on reactivex.io](http://reactivex.io/documentation/operators/create.html)

     - parameter subscribe: Implementation of the resulting observable sequence's `subscribe` method.
     - returns: The observable sequence with the specified implementation for the `subscribe` method.
     */
    public static func create(subscribe: @escaping (@escaping SingleObserver) -> Disposable) -> PrimitiveSequence<TraitType, ElementType> {
        let source = Observable<ElementType>.create { observer in
            return subscribe { event in
                switch event {
                case .success(let element):
                    observer.on(.next(element))
                    observer.on(.completed)
                case .error(let error):
                    observer.on(.error(error))
                }
            }
        }

        return PrimitiveSequence(raw: source)
    }


    /**
     Subscribes `observer` to receive events for this sequence.

     - returns: Subscription for `observer` that can be used to cancel production of sequence elements and free resources.
     */
    public func subscribe(_ observer: @escaping (SingleEvent<ElementType>) -> ()) -> Disposable {
        var stopped = false
        return self.primitiveSequence.asObservable().subscribe { event in
            if stopped { return }
            stopped = true

            switch event {
            case .next(let element):
                observer(.success(element))
            case .error(let error):
                observer(.error(error))
            case .completed:
                rxFatalErrorInDebug("Singles can't emit a completion event")
            }
        }
    }

    /**
     Subscribes a success handler, and an error handler for this sequence.

     - parameter onSuccess: Action to invoke for each element in the observable sequence.
     - parameter onError: Action to invoke upon errored termination of the observable sequence.
     - returns: Subscription object used to unsubscribe from the observable sequence.
     */
    public func subscribe(onSuccess: ((ElementType) -> Void)? = nil, onError: ((Swift.Error) -> Void)? = nil) -> Disposable {
        return self.primitiveSequence.subscribe { event in
            switch event {
            case .success(let element):
                onSuccess?(element)
            case .error(let error):
                onError?(error)
            }
        }
    }
}

// </Single>

// <Maybe>

public enum MaybeEvent<Element> {
    /// One and only sequence element is produced. (underlying observable sequence emits: `.next(Element)`, `.completed`)
    case success(Element)

    /// Sequence terminated with an error. (underlying observable sequence emits: `.error(Error)`)
    case error(Swift.Error)

    /// Sequence completed successfully.
    case completed
}

public extension PrimitiveSequenceType where TraitType == MaybeTrait {
    public typealias MaybeObserver = (MaybeEvent<ElementType>) -> ()

    /**
     Creates an observable sequence from a specified subscribe method implementation.

     - seealso: [create operator on reactivex.io](http://reactivex.io/documentation/operators/create.html)

     - parameter subscribe: Implementation of the resulting observable sequence's `subscribe` method.
     - returns: The observable sequence with the specified implementation for the `subscribe` method.
     */
    public static func create(subscribe: @escaping (@escaping MaybeObserver) -> Disposable) -> PrimitiveSequence<TraitType, ElementType> {
        let source = Observable<ElementType>.create { observer in
            return subscribe { event in
                switch event {
                case .success(let element):
                    observer.on(.next(element))
                    observer.on(.completed)
                case .error(let error):
                    observer.on(.error(error))
                case .completed:
                    observer.on(.completed)
                }
            }
        }

        return PrimitiveSequence(raw: source)
    }

    /**
     Subscribes `observer` to receive events for this sequence.

     - returns: Subscription for `observer` that can be used to cancel production of sequence elements and free resources.
     */
    public func subscribe(_ observer: @escaping (MaybeEvent<ElementType>) -> ()) -> Disposable {
        var stopped = false
        return self.primitiveSequence.asObservable().subscribe { event in
            if stopped { return }
            stopped = true

            switch event {
            case .next(let element):
                observer(.success(element))
            case .error(let error):
                observer(.error(error))
            case .completed:
                observer(.completed)
            }
        }
    }

    /**
     Subscribes a success handler, an error handler, and a completion handler for this sequence.

     - parameter onSuccess: Action to invoke for each element in the observable sequence.
     - parameter onError: Action to invoke upon errored termination of the observable sequence.
     - parameter onCompleted: Action to invoke upon graceful termination of the observable sequence.
     - returns: Subscription object used to unsubscribe from the observable sequence.
     */
    public func subscribe(onSuccess: ((ElementType) -> Void)? = nil, onError: ((Swift.Error) -> Void)? = nil, onCompleted: (() -> Void)? = nil) -> Disposable {
        return self.primitiveSequence.subscribe { event in
            switch event {
            case .success(let element):
                onSuccess?(element)
            case .error(let error):
                onError?(error)
            case .completed:
                onCompleted?()
            }
        }
    }
}

// </Maybe>

// <Completable>

public enum CompletableEvent {
    /// Sequence terminated with an error. (underlying observable sequence emits: `.error(Error)`)
    case error(Swift.Error)

    /// Sequence completed successfully.
    case completed
}

public extension PrimitiveSequenceType where TraitType == CompletableTrait, ElementType == Swift.Never {
    public typealias CompletableObserver = (CompletableEvent) -> ()

    /**
     Creates an observable sequence from a specified subscribe method implementation.

     - seealso: [create operator on reactivex.io](http://reactivex.io/documentation/operators/create.html)

     - parameter subscribe: Implementation of the resulting observable sequence's `subscribe` method.
     - returns: The observable sequence with the specified implementation for the `subscribe` method.
     */
    public static func create(subscribe: @escaping (@escaping CompletableObserver) -> Disposable) -> PrimitiveSequence<TraitType, ElementType> {
        let source = Observable<ElementType>.create { observer in
            return subscribe { event in
                switch event {
                case .error(let error):
                    observer.on(.error(error))
                case .completed:
                    observer.on(.completed)
                }
            }
        }

        return PrimitiveSequence(raw: source)
    }

    /**
     Subscribes `observer` to receive events for this sequence.

     - returns: Subscription for `observer` that can be used to cancel production of sequence elements and free resources.
     */
    public func subscribe(_ observer: @escaping (CompletableEvent) -> ()) -> Disposable {
        var stopped = false
        return self.primitiveSequence.asObservable().subscribe { event in
            if stopped { return }
            stopped = true

            switch event {
            case .next:
                rxFatalError("Completables can't emit values")
            case .error(let error):
                observer(.error(error))
            case .completed:
                observer(.completed)
            }
        }
    }

    /**
     Subscribes a completion handler and an error handler for this sequence.

     - parameter onCompleted: Action to invoke upon graceful termination of the observable sequence.
     - parameter onError: Action to invoke upon errored termination of the observable sequence.
     - returns: Subscription object used to unsubscribe from the observable sequence.
     */
    public func subscribe(onCompleted: (() -> Void)? = nil, onError: ((Swift.Error) -> Void)? = nil) -> Disposable {
        return self.primitiveSequence.subscribe { event in
            switch event {
            case .error(let error):
                onError?(error)
            case .completed:
                onCompleted?()
            }
        }
    }
}

// </Completable>

extension PrimitiveSequence {
    /**
     Returns an observable sequence that invokes the specified factory function whenever a new observer subscribes.

     - seealso: [defer operator on reactivex.io](http://reactivex.io/documentation/operators/defer.html)

     - parameter observableFactory: Observable factory function to invoke for each observer that subscribes to the resulting sequence.
     - returns: An observable sequence whose observers trigger an invocation of the given observable factory function.
     */
    public static func deferred(_ observableFactory: @escaping () throws -> PrimitiveSequence<Trait, Element>)
        -> PrimitiveSequence<Trait, Element> {
        return PrimitiveSequence(raw: Observable.deferred {
            try observableFactory().asObservable()
        })
    }

    /**
     Returns an observable sequence that contains a single element.

     - seealso: [just operator on reactivex.io](http://reactivex.io/documentation/operators/just.html)

     - parameter element: Single element in the resulting observable sequence.
     - returns: An observable sequence containing the single specified element.
     */
    public static func just(_ element: Element) -> PrimitiveSequence<Trait, ElementType> {
        return PrimitiveSequence(raw: Observable.just(element))
    }

    /**
     Returns an observable sequence that contains a single element.

     - seealso: [just operator on reactivex.io](http://reactivex.io/documentation/operators/just.html)

     - parameter element: Single element in the resulting observable sequence.
     - parameter: Scheduler to send the single element on.
     - returns: An observable sequence containing the single specified element.
     */
    public static func just(_ element: Element, scheduler: ImmediateSchedulerType) -> PrimitiveSequence<Trait, ElementType> {
        return PrimitiveSequence(raw: Observable.just(element, scheduler: scheduler))
    }

    /**
     Returns an observable sequence that terminates with an `error`.

     - seealso: [throw operator on reactivex.io](http://reactivex.io/documentation/operators/empty-never-throw.html)

     - returns: The observable sequence that terminates with specified error.
     */
    public static func error(_ error: Swift.Error) -> PrimitiveSequence<Trait, Element> {
        return PrimitiveSequence(raw: Observable.error(error))
    }


    /**
     Returns a non-terminating observable sequence, which can be used to denote an infinite duration.

     - seealso: [never operator on reactivex.io](http://reactivex.io/documentation/operators/empty-never-throw.html)

     - returns: An observable sequence whose observers will never get called.
     */
    public static func never() -> PrimitiveSequence<Trait, Element> {
        return PrimitiveSequence(raw: Observable.never())
    }

    /**
     Time shifts the observable sequence by delaying the subscription with the specified relative time duration, using the specified scheduler to run timers.

     - seealso: [delay operator on reactivex.io](http://reactivex.io/documentation/operators/delay.html)

     - parameter dueTime: Relative time shift of the subscription.
     - parameter scheduler: Scheduler to run the subscription delay timer on.
     - returns: Time-shifted sequence.
     */
    public func delaySubscription(_ dueTime: RxTimeInterval, scheduler: SchedulerType)
        -> PrimitiveSequence<Trait, Element> {
        return PrimitiveSequence(raw: source.delaySubscription(dueTime, scheduler: scheduler))
    }

    /**
     Returns an observable sequence by the source observable sequence shifted forward in time by a specified delay. Error events from the source observable sequence are not delayed.

     - seealso: [delay operator on reactivex.io](http://reactivex.io/documentation/operators/delay.html)

     - parameter dueTime: Relative time shift of the source by.
     - parameter scheduler: Scheduler to run the subscription delay timer on.
     - returns: the source Observable shifted in time by the specified delay.
     */
    public func delay(_ dueTime: RxTimeInterval, scheduler: SchedulerType)
        -> PrimitiveSequence<Trait, Element> {
        return PrimitiveSequence(raw: source.delay(dueTime, scheduler: scheduler))
    }

    /**
     Invokes an action for each event in the observable sequence, and propagates all observer messages through the result sequence.

     - seealso: [do operator on reactivex.io](http://reactivex.io/documentation/operators/do.html)

     - parameter onNext: Action to invoke for each element in the observable sequence.
     - parameter onError: Action to invoke upon errored termination of the observable sequence.
     - parameter onCompleted: Action to invoke upon graceful termination of the observable sequence.
     - parameter onSubscribe: Action to invoke before subscribing to source observable sequence.
     - parameter onSubscribed: Action to invoke after subscribing to source observable sequence.
     - parameter onDispose: Action to invoke after subscription to source observable has been disposed for any reason. It can be either because sequence terminates for some reason or observer subscription being disposed.
     - returns: The source sequence with the side-effecting behavior applied.
     */
    public func `do`(onNext: ((E) throws -> Void)? = nil, onError: ((Swift.Error) throws -> Void)? = nil, onCompleted: (() throws -> Void)? = nil, onSubscribe: (() -> ())? = nil, onSubscribed: (() -> ())? = nil, onDispose: (() -> ())? = nil)
        -> PrimitiveSequence<Trait, Element> {
            return PrimitiveSequence(raw: source.do(
                onNext: onNext,
                onError: onError,
                onCompleted: onCompleted,
                onSubscribe: onSubscribe,
                onSubscribed: onSubscribed,
                onDispose: onDispose)
            )
    }

    /**
     Filters the elements of an observable sequence based on a predicate.

     - seealso: [filter operator on reactivex.io](http://reactivex.io/documentation/operators/filter.html)

     - parameter predicate: A function to test each source element for a condition.
     - returns: An observable sequence that contains elements from the input sequence that satisfy the condition.
     */
    public func filter(_ predicate: @escaping (E) throws -> Bool)
        -> Maybe<Element> {
        return Maybe(raw: source.filter(predicate))
    }

    /**
     Projects each element of an observable sequence into a new form.

     - seealso: [map operator on reactivex.io](http://reactivex.io/documentation/operators/map.html)

     - parameter transform: A transform function to apply to each source element.
     - returns: An observable sequence whose elements are the result of invoking the transform function on each element of source.

     */
    public func map<R>(_ transform: @escaping (E) throws -> R)
        -> PrimitiveSequence<Trait, R> {
        return PrimitiveSequence<Trait, R>(raw: source.map(transform))
    }

    /**
     Projects each element of an observable sequence to an observable sequence and merges the resulting observable sequences into one observable sequence.

     - seealso: [flatMap operator on reactivex.io](http://reactivex.io/documentation/operators/flatmap.html)

     - parameter selector: A transform function to apply to each element.
     - returns: An observable sequence whose elements are the result of invoking the one-to-many transform function on each element of the input sequence.
     */
    public func flatMap<R>(_ selector: @escaping (ElementType) throws -> PrimitiveSequence<Trait, R>)
        -> PrimitiveSequence<Trait, R> {
        return PrimitiveSequence<Trait, R>(raw: source.flatMap(selector))
    }

    /**
     Wraps the source sequence in order to run its observer callbacks on the specified scheduler.

     This only invokes observer callbacks on a `scheduler`. In case the subscription and/or unsubscription
     actions have side-effects that require to be run on a scheduler, use `subscribeOn`.

     - seealso: [observeOn operator on reactivex.io](http://reactivex.io/documentation/operators/observeon.html)

     - parameter scheduler: Scheduler to notify observers on.
     - returns: The source sequence whose observations happen on the specified scheduler.
     */
    public func observeOn(_ scheduler: ImmediateSchedulerType)
        -> PrimitiveSequence<Trait, Element> {
        return PrimitiveSequence(raw: source.observeOn(scheduler))
    }

    /**
    Wraps the source sequence in order to run its subscription and unsubscription logic on the specified 
    scheduler. 
    
    This operation is not commonly used.
    
    This only performs the side-effects of subscription and unsubscription on the specified scheduler. 
    
    In order to invoke observer callbacks on a `scheduler`, use `observeOn`.

    - seealso: [subscribeOn operator on reactivex.io](http://reactivex.io/documentation/operators/subscribeon.html)
    
    - parameter scheduler: Scheduler to perform subscription and unsubscription actions on.
    - returns: The source sequence whose subscriptions and unsubscriptions happen on the specified scheduler.
    */
    public func subscribeOn(_ scheduler: ImmediateSchedulerType)
        -> PrimitiveSequence<Trait, Element> {
        return PrimitiveSequence(raw: source.subscribeOn(scheduler))
    }

    /**
     Continues an observable sequence that is terminated by an error with the observable sequence produced by the handler.

     - seealso: [catch operator on reactivex.io](http://reactivex.io/documentation/operators/catch.html)

     - parameter handler: Error handler function, producing another observable sequence.
     - returns: An observable sequence containing the source sequence's elements, followed by the elements produced by the handler's resulting observable sequence in case an error occurred.
     */
    public func catchError(_ handler: @escaping (Swift.Error) throws -> PrimitiveSequence<Trait, Element>)
        -> PrimitiveSequence<Trait, Element> {
        return PrimitiveSequence(raw: source.catchError { try handler($0).asObservable() })
    }

    /**
     Repeats the source observable sequence the specified number of times in case of an error or until it successfully terminates.

     If you encounter an error and want it to retry once, then you must use `retry(2)`

     - seealso: [retry operator on reactivex.io](http://reactivex.io/documentation/operators/retry.html)

     - parameter maxAttemptCount: Maximum number of times to repeat the sequence.
     - returns: An observable sequence producing the elements of the given sequence repeatedly until it terminates successfully.
     */
    public func retry(_ maxAttemptCount: Int)
        -> PrimitiveSequence<Trait, Element> {
        return PrimitiveSequence(raw: source.retry(maxAttemptCount))
    }

    /**
     Repeats the source observable sequence on error when the notifier emits a next value.
     If the source observable errors and the notifier completes, it will complete the source sequence.

     - seealso: [retry operator on reactivex.io](http://reactivex.io/documentation/operators/retry.html)

     - parameter notificationHandler: A handler that is passed an observable sequence of errors raised by the source observable and returns and observable that either continues, completes or errors. This behavior is then applied to the source observable.
     - returns: An observable sequence producing the elements of the given sequence repeatedly until it terminates successfully or is notified to error or complete.
     */
    public func retryWhen<TriggerObservable: ObservableType, Error: Swift.Error>(_ notificationHandler: @escaping (Observable<Error>) -> TriggerObservable)
        -> PrimitiveSequence<Trait, Element> {
        return PrimitiveSequence(raw: source.retryWhen(notificationHandler))
    }

    /**
     Repeats the source observable sequence on error when the notifier emits a next value.
     If the source observable errors and the notifier completes, it will complete the source sequence.

     - seealso: [retry operator on reactivex.io](http://reactivex.io/documentation/operators/retry.html)

     - parameter notificationHandler: A handler that is passed an observable sequence of errors raised by the source observable and returns and observable that either continues, completes or errors. This behavior is then applied to the source observable.
     - returns: An observable sequence producing the elements of the given sequence repeatedly until it terminates successfully or is notified to error or complete.
     */
    public func retryWhen<TriggerObservable: ObservableType>(_ notificationHandler: @escaping (Observable<Swift.Error>) -> TriggerObservable)
        -> PrimitiveSequence<Trait, Element> {
        return PrimitiveSequence(raw: source.retryWhen(notificationHandler))
    }

    /**
     Prints received events for all observers on standard output.

     - seealso: [do operator on reactivex.io](http://reactivex.io/documentation/operators/do.html)

     - parameter identifier: Identifier that is printed together with event description to standard output.
     - parameter trimOutput: Should output be trimmed to max 40 characters.
     - returns: An observable sequence whose events are printed to standard output.
     */
    public func debug(_ identifier: String? = nil, trimOutput: Bool = false, file: String = #file, line: UInt = #line, function: String = #function)
        -> PrimitiveSequence<Trait, Element> {
            return PrimitiveSequence(raw: source.debug(identifier, trimOutput: trimOutput, file: file, line: line, function: function))
    }
    
    /**
     Constructs an observable sequence that depends on a resource object, whose lifetime is tied to the resulting observable sequence's lifetime.
     
     - seealso: [using operator on reactivex.io](http://reactivex.io/documentation/operators/using.html)
     
     - parameter resourceFactory: Factory function to obtain a resource object.
     - parameter primitiveSequenceFactory: Factory function to obtain an observable sequence that depends on the obtained resource.
     - returns: An observable sequence whose lifetime controls the lifetime of the dependent resource object.
     */
    public static func using<Resource: Disposable>(_ resourceFactory: @escaping () throws -> Resource, primitiveSequenceFactory: @escaping (Resource) throws -> PrimitiveSequence<Trait, Element>)
        -> PrimitiveSequence<Trait, Element> {
            return PrimitiveSequence(raw: Observable.using(resourceFactory, observableFactory: { (resource: Resource) throws -> Observable<E> in
                return try primitiveSequenceFactory(resource).asObservable()
            }))
    }

    /**
     Applies a timeout policy for each element in the observable sequence. If the next element isn't received within the specified timeout duration starting from its predecessor, a TimeoutError is propagated to the observer.

     - seealso: [timeout operator on reactivex.io](http://reactivex.io/documentation/operators/timeout.html)

     - parameter dueTime: Maximum duration between values before a timeout occurs.
     - parameter scheduler: Scheduler to run the timeout timer on.
     - returns: An observable sequence with a `RxError.timeout` in case of a timeout.
     */
    public func timeout(_ dueTime: RxTimeInterval, scheduler: SchedulerType)
        -> PrimitiveSequence<Trait, Element> {
        return PrimitiveSequence(raw: source.timeout(dueTime, scheduler: scheduler))
    }

    /**
     Applies a timeout policy for each element in the observable sequence, using the specified scheduler to run timeout timers. If the next element isn't received within the specified timeout duration starting from its predecessor, the other observable sequence is used to produce future messages from that point on.

     - seealso: [timeout operator on reactivex.io](http://reactivex.io/documentation/operators/timeout.html)

     - parameter dueTime: Maximum duration between values before a timeout occurs.
     - parameter other: Sequence to return in case of a timeout.
     - parameter scheduler: Scheduler to run the timeout timer on.
     - returns: The source sequence switching to the other sequence in case of a timeout.
     */
    public func timeout(_ dueTime: RxTimeInterval, other: PrimitiveSequence<Trait, Element>, scheduler: SchedulerType)
        -> PrimitiveSequence<Trait, Element> {
        return PrimitiveSequence(raw: source.timeout(dueTime, other: other.source, scheduler: scheduler))
    }
}

extension PrimitiveSequenceType where ElementType: SignedInteger
{
    /**
     Returns an observable sequence that periodically produces a value after the specified initial relative due time has elapsed, using the specified scheduler to run timers.

     - seealso: [timer operator on reactivex.io](http://reactivex.io/documentation/operators/timer.html)

     - parameter dueTime: Relative time at which to produce the first value.
     - parameter scheduler: Scheduler to run timers on.
     - returns: An observable sequence that produces a value after due time has elapsed and then each period.
     */
    public static func timer(_ dueTime: RxTimeInterval, scheduler: SchedulerType)
        -> PrimitiveSequence<TraitType, ElementType>  {
        return PrimitiveSequence(raw: Observable<ElementType>.timer(dueTime, scheduler: scheduler))
    }
}

extension PrimitiveSequenceType where TraitType == MaybeTrait {
    /**
     Returns an empty observable sequence, using the specified scheduler to send out the single `Completed` message.

     - seealso: [empty operator on reactivex.io](http://reactivex.io/documentation/operators/empty-never-throw.html)

     - returns: An observable sequence with no elements.
     */
    public static func empty() -> PrimitiveSequence<MaybeTrait, ElementType> {
        return PrimitiveSequence(raw: Observable.empty())
    }
}

extension PrimitiveSequenceType where TraitType == CompletableTrait, ElementType == Never {
    /**
     Returns an empty observable sequence, using the specified scheduler to send out the single `Completed` message.

     - seealso: [empty operator on reactivex.io](http://reactivex.io/documentation/operators/empty-never-throw.html)

     - returns: An observable sequence with no elements.
     */
    public static func empty() -> PrimitiveSequence<CompletableTrait, Never> {
        return PrimitiveSequence(raw: Observable.empty())
    }
    
    /**
     Concatenates the second observable sequence to `self` upon successful termination of `self`.
     
     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)
     
     - parameter second: Second observable sequence.
     - returns: An observable sequence that contains the elements of `self`, followed by those of the second sequence.
     */
    public func concat(_ second: PrimitiveSequence<CompletableTrait, Never>) -> PrimitiveSequence<CompletableTrait, Never> {
        return Completable.concat(primitiveSequence, second)
    }
    
    /**
     Concatenates all observable sequences in the given sequence, as long as the previous observable sequence terminated successfully.
     
     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)
     
     - returns: An observable sequence that contains the elements of each given sequence, in sequential order.
     */
    public static func concat<S: Sequence>(_ sequence: S) -> PrimitiveSequence<CompletableTrait, Never>
        where S.Iterator.Element == PrimitiveSequence<CompletableTrait, Never> {
            let source = Observable.concat(sequence.lazy.map { $0.asObservable() })
            return PrimitiveSequence<CompletableTrait, Never>(raw: source)
    }
    
    /**
     Concatenates all observable sequences in the given sequence, as long as the previous observable sequence terminated successfully.
     
     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)
     
     - returns: An observable sequence that contains the elements of each given sequence, in sequential order.
     */
    public static func concat<C: Collection>(_ collection: C) -> PrimitiveSequence<CompletableTrait, Never>
        where C.Iterator.Element == PrimitiveSequence<CompletableTrait, Never> {
            let source = Observable.concat(collection.map { $0.asObservable() })
            return PrimitiveSequence<CompletableTrait, Never>(raw: source)
    }
    
    /**
     Concatenates all observable sequences in the given sequence, as long as the previous observable sequence terminated successfully.
     
     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)
     
     - returns: An observable sequence that contains the elements of each given sequence, in sequential order.
     */
    public static func concat(_ sources: PrimitiveSequence<CompletableTrait, Never> ...) -> PrimitiveSequence<CompletableTrait, Never> {
        let source = Observable.concat(sources.map { $0.asObservable() })
        return PrimitiveSequence<CompletableTrait, Never>(raw: source)
    }
    
    /**
     Merges elements from all observable sequences from collection into a single observable sequence.
     
     - seealso: [merge operator on reactivex.io](http://reactivex.io/documentation/operators/merge.html)
     
     - parameter sources: Collection of observable sequences to merge.
     - returns: The observable sequence that merges the elements of the observable sequences.
     */
    public static func merge<C: Collection>(_ sources: C) -> PrimitiveSequence<CompletableTrait, Never>
        where C.Iterator.Element == PrimitiveSequence<CompletableTrait, Never> {
            let source = Observable.merge(sources.map { $0.asObservable() })
            return PrimitiveSequence<CompletableTrait, Never>(raw: source)
    }
    
    /**
     Merges elements from all observable sequences from array into a single observable sequence.
     
     - seealso: [merge operator on reactivex.io](http://reactivex.io/documentation/operators/merge.html)
     
     - parameter sources: Array of observable sequences to merge.
     - returns: The observable sequence that merges the elements of the observable sequences.
     */
    public static func merge(_ sources: [PrimitiveSequence<CompletableTrait, Never>]) -> PrimitiveSequence<CompletableTrait, Never> {
        let source = Observable.merge(sources.map { $0.asObservable() })
        return PrimitiveSequence<CompletableTrait, Never>(raw: source)
    }
    
    /**
     Merges elements from all observable sequences into a single observable sequence.
     
     - seealso: [merge operator on reactivex.io](http://reactivex.io/documentation/operators/merge.html)
     
     - parameter sources: Collection of observable sequences to merge.
     - returns: The observable sequence that merges the elements of the observable sequences.
     */
    public static func merge(_ sources: PrimitiveSequence<CompletableTrait, Never>...) -> PrimitiveSequence<CompletableTrait, Never> {
        let source = Observable.merge(sources.map { $0.asObservable() })
        return PrimitiveSequence<CompletableTrait, Never>(raw: source)
    }
}

extension ObservableType {
    /**
     The `asSingle` operator throws a `RxError.noElements` or `RxError.moreThanOneElement`
     if the source Observable does not emit exactly one element before successfully completing.

     - seealso: [single operator on reactivex.io](http://reactivex.io/documentation/operators/first.html)

     - returns: An observable sequence that emits a single element or throws an exception if more (or none) of them are emitted.
     */
    public func asSingle() -> Single<E> {
        return PrimitiveSequence(raw: AsSingle(source: self.asObservable()))
    }

    /**
     The `asMaybe` operator throws a ``RxError.moreThanOneElement`
     if the source Observable does not emit at most one element before successfully completing.

     - seealso: [single operator on reactivex.io](http://reactivex.io/documentation/operators/first.html)

     - returns: An observable sequence that emits a single element, completes or throws an exception if more of them are emitted.
     */
    public func asMaybe() -> Maybe<E> {
        return PrimitiveSequence(raw: AsMaybe(source: self.asObservable()))
    }
}

extension ObservableType where E == Never {
    /**
    - returns: An observable sequence that completes.
     */
    public func asCompletable()
        -> Completable {
        return PrimitiveSequence(raw: self.asObservable())
    }
}
