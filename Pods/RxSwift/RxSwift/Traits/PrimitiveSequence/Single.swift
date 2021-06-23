//
//  Single.swift
//  RxSwift
//
//  Created by sergdort on 19/08/2017.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

#if DEBUG
import Foundation
#endif

/// Sequence containing exactly 1 element
public enum SingleTrait { }
/// Represents a push style sequence containing 1 element.
public typealias Single<Element> = PrimitiveSequence<SingleTrait, Element>
public typealias SingleEvent<Element> = Result<Element, Swift.Error>

extension PrimitiveSequenceType where Trait == SingleTrait {
    public typealias SingleObserver = (SingleEvent<Element>) -> Void
    
    /**
     Creates an observable sequence from a specified subscribe method implementation.
     
     - seealso: [create operator on reactivex.io](http://reactivex.io/documentation/operators/create.html)
     
     - parameter subscribe: Implementation of the resulting observable sequence's `subscribe` method.
     - returns: The observable sequence with the specified implementation for the `subscribe` method.
     */
    public static func create(subscribe: @escaping (@escaping SingleObserver) -> Disposable) -> Single<Element> {
        let source = Observable<Element>.create { observer in
            return subscribe { event in
                switch event {
                case .success(let element):
                    observer.on(.next(element))
                    observer.on(.completed)
                case .failure(let error):
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
    public func subscribe(_ observer: @escaping (SingleEvent<Element>) -> Void) -> Disposable {
        var stopped = false
        return self.primitiveSequence.asObservable().subscribe { event in
            if stopped { return }
            stopped = true
            
            switch event {
            case .next(let element):
                observer(.success(element))
            case .error(let error):
                observer(.failure(error))
            case .completed:
                rxFatalErrorInDebug("Singles can't emit a completion event")
            }
        }
    }

    /**
     Subscribes a success handler, and an error handler for this sequence.

     - parameter onSuccess: Action to invoke for each element in the observable sequence.
     - parameter onError: Action to invoke upon errored termination of the observable sequence.
     - parameter onDisposed: Action to invoke upon any type of termination of sequence (if the sequence has
     gracefully completed, errored, or if the generation is canceled by disposing subscription).
     - returns: Subscription object used to unsubscribe from the observable sequence.
     */
    @available(*, deprecated, renamed: "subscribe(onSuccess:onFailure:onDisposed:)")
    public func subscribe(onSuccess: ((Element) -> Void)? = nil,
                          onError: @escaping ((Swift.Error) -> Void),
                          onDisposed: (() -> Void)? = nil) -> Disposable {
        subscribe(onSuccess: onSuccess, onFailure: onError, onDisposed: onDisposed)
    }
    
    /**
     Subscribes a success handler, and an error handler for this sequence.
     
     Also, take in an object and provide an unretained, safe to use (i.e. not implicitly unwrapped), reference to it along with the events emitted by the sequence.
     
     - Note: If `object` can't be retained, none of the other closures will be invoked.
     
     - parameter object: The object to provide an unretained reference on.
     - parameter onSuccess: Action to invoke for each element in the observable sequence.
     - parameter onFailure: Action to invoke upon errored termination of the observable sequence.
     - parameter onDisposed: Action to invoke upon any type of termination of sequence (if the sequence has
     gracefully completed, errored, or if the generation is canceled by disposing subscription).
     - returns: Subscription object used to unsubscribe from the observable sequence.
     */
    public func subscribe<Object: AnyObject>(
        with object: Object,
        onSuccess: ((Object, Element) -> Void)? = nil,
        onFailure: ((Object, Swift.Error) -> Void)? = nil,
        onDisposed: ((Object) -> Void)? = nil
    ) -> Disposable {
        subscribe(
            onSuccess: { [weak object] in
                guard let object = object else { return }
                onSuccess?(object, $0)
            },
            onFailure: { [weak object] in
                guard let object = object else { return }
                onFailure?(object, $0)
            },
            onDisposed: { [weak object] in
                guard let object = object else { return }
                onDisposed?(object)
            }
        )
    }
    
    /**
     Subscribes a success handler, and an error handler for this sequence.
     
     - parameter onSuccess: Action to invoke for each element in the observable sequence.
     - parameter onFailure: Action to invoke upon errored termination of the observable sequence.
     - parameter onDisposed: Action to invoke upon any type of termination of sequence (if the sequence has
     gracefully completed, errored, or if the generation is canceled by disposing subscription).
     - returns: Subscription object used to unsubscribe from the observable sequence.
     */
    public func subscribe(onSuccess: ((Element) -> Void)? = nil,
                          onFailure: ((Swift.Error) -> Void)? = nil,
                          onDisposed: (() -> Void)? = nil) -> Disposable {
        #if DEBUG
            let callStack = Hooks.recordCallStackOnError ? Thread.callStackSymbols : []
        #else
            let callStack = [String]()
        #endif

        let disposable: Disposable
        if let onDisposed = onDisposed {
            disposable = Disposables.create(with: onDisposed)
        } else {
            disposable = Disposables.create()
        }

        let observer: SingleObserver = { event in
            switch event {
            case .success(let element):
                onSuccess?(element)
                disposable.dispose()
            case .failure(let error):
                if let onFailure = onFailure {
                    onFailure(error)
                } else {
                    Hooks.defaultErrorHandler(callStack, error)
                }
                disposable.dispose()
            }
        }

        return Disposables.create(
            self.primitiveSequence.subscribe(observer),
            disposable
        )
    }
}

extension PrimitiveSequenceType where Trait == SingleTrait {
    /**
     Returns an observable sequence that contains a single element.
     
     - seealso: [just operator on reactivex.io](http://reactivex.io/documentation/operators/just.html)
     
     - parameter element: Single element in the resulting observable sequence.
     - returns: An observable sequence containing the single specified element.
     */
    public static func just(_ element: Element) -> Single<Element> {
        Single(raw: Observable.just(element))
    }
    
    /**
     Returns an observable sequence that contains a single element.
     
     - seealso: [just operator on reactivex.io](http://reactivex.io/documentation/operators/just.html)
     
     - parameter element: Single element in the resulting observable sequence.
     - parameter scheduler: Scheduler to send the single element on.
     - returns: An observable sequence containing the single specified element.
     */
    public static func just(_ element: Element, scheduler: ImmediateSchedulerType) -> Single<Element> {
        Single(raw: Observable.just(element, scheduler: scheduler))
    }

    /**
     Returns an observable sequence that terminates with an `error`.

     - seealso: [throw operator on reactivex.io](http://reactivex.io/documentation/operators/empty-never-throw.html)

     - returns: The observable sequence that terminates with specified error.
     */
    public static func error(_ error: Swift.Error) -> Single<Element> {
        PrimitiveSequence(raw: Observable.error(error))
    }

    /**
     Returns a non-terminating observable sequence, which can be used to denote an infinite duration.

     - seealso: [never operator on reactivex.io](http://reactivex.io/documentation/operators/empty-never-throw.html)

     - returns: An observable sequence whose observers will never get called.
     */
    public static func never() -> Single<Element> {
        PrimitiveSequence(raw: Observable.never())
    }
}

extension PrimitiveSequenceType where Trait == SingleTrait {

    /**
     Invokes an action for each event in the observable sequence, and propagates all observer messages through the result sequence.

     - seealso: [do operator on reactivex.io](http://reactivex.io/documentation/operators/do.html)

     - parameter onSuccess: Action to invoke for each element in the observable sequence.
     - parameter afterSuccess: Action to invoke for each element after the observable has passed an onNext event along to its downstream.
     - parameter onError: Action to invoke upon errored termination of the observable sequence.
     - parameter afterError: Action to invoke after errored termination of the observable sequence.
     - parameter onSubscribe: Action to invoke before subscribing to source observable sequence.
     - parameter onSubscribed: Action to invoke after subscribing to source observable sequence.
     - parameter onDispose: Action to invoke after subscription to source observable has been disposed for any reason. It can be either because sequence terminates for some reason or observer subscription being disposed.
     - returns: The source sequence with the side-effecting behavior applied.
     */
    public func `do`(onSuccess: ((Element) throws -> Void)? = nil,
                     afterSuccess: ((Element) throws -> Void)? = nil,
                     onError: ((Swift.Error) throws -> Void)? = nil,
                     afterError: ((Swift.Error) throws -> Void)? = nil,
                     onSubscribe: (() -> Void)? = nil,
                     onSubscribed: (() -> Void)? = nil,
                     onDispose: (() -> Void)? = nil)
        -> Single<Element> {
            return Single(raw: self.primitiveSequence.source.do(
                onNext: onSuccess,
                afterNext: afterSuccess,
                onError: onError,
                afterError: afterError,
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
    public func filter(_ predicate: @escaping (Element) throws -> Bool)
        -> Maybe<Element> {
            return Maybe(raw: self.primitiveSequence.source.filter(predicate))
    }

    /**
     Projects each element of an observable sequence into a new form.
     
     - seealso: [map operator on reactivex.io](http://reactivex.io/documentation/operators/map.html)
     
     - parameter transform: A transform function to apply to each source element.
     - returns: An observable sequence whose elements are the result of invoking the transform function on each element of source.
     
     */
    public func map<Result>(_ transform: @escaping (Element) throws -> Result)
        -> Single<Result> {
            return Single(raw: self.primitiveSequence.source.map(transform))
    }
    
    /**
     Projects each element of an observable sequence into an optional form and filters all optional results.

     - parameter transform: A transform function to apply to each source element.
     - returns: An observable sequence whose elements are the result of filtering the transform function for each element of the source.

     */
    public func compactMap<Result>(_ transform: @escaping (Element) throws -> Result?)
        -> Maybe<Result> {
        Maybe(raw: self.primitiveSequence.source.compactMap(transform))
    }
    
    /**
     Projects each element of an observable sequence to an observable sequence and merges the resulting observable sequences into one observable sequence.
     
     - seealso: [flatMap operator on reactivex.io](http://reactivex.io/documentation/operators/flatmap.html)
     
     - parameter selector: A transform function to apply to each element.
     - returns: An observable sequence whose elements are the result of invoking the one-to-many transform function on each element of the input sequence.
     */
    public func flatMap<Result>(_ selector: @escaping (Element) throws -> Single<Result>)
        -> Single<Result> {
            return Single<Result>(raw: self.primitiveSequence.source.flatMap(selector))
    }

    /**
     Projects each element of an observable sequence to an observable sequence and merges the resulting observable sequences into one observable sequence.

     - seealso: [flatMap operator on reactivex.io](http://reactivex.io/documentation/operators/flatmap.html)

     - parameter selector: A transform function to apply to each element.
     - returns: An observable sequence whose elements are the result of invoking the one-to-many transform function on each element of the input sequence.
     */
    public func flatMapMaybe<Result>(_ selector: @escaping (Element) throws -> Maybe<Result>)
        -> Maybe<Result> {
            return Maybe<Result>(raw: self.primitiveSequence.source.flatMap(selector))
    }

    /**
     Projects each element of an observable sequence to an observable sequence and merges the resulting observable sequences into one observable sequence.

     - seealso: [flatMap operator on reactivex.io](http://reactivex.io/documentation/operators/flatmap.html)

     - parameter selector: A transform function to apply to each element.
     - returns: An observable sequence whose elements are the result of invoking the one-to-many transform function on each element of the input sequence.
     */
    public func flatMapCompletable(_ selector: @escaping (Element) throws -> Completable)
        -> Completable {
            return Completable(raw: self.primitiveSequence.source.flatMap(selector))
    }

    /**
     Merges the specified observable sequences into one observable sequence by using the selector function whenever all of the observable sequences have produced an element at a corresponding index.
     
     - parameter resultSelector: Function to invoke for each series of elements at corresponding indexes in the sources.
     - returns: An observable sequence containing the result of combining elements of the sources using the specified result selector function.
     */
    public static func zip<Collection: Swift.Collection, Result>(_ collection: Collection, resultSelector: @escaping ([Element]) throws -> Result) -> PrimitiveSequence<Trait, Result> where Collection.Element == PrimitiveSequence<Trait, Element> {
        
        if collection.isEmpty {
            return PrimitiveSequence<Trait, Result>.deferred {
                return PrimitiveSequence<Trait, Result>(raw: .just(try resultSelector([])))
            }
        }
        
        let raw = Observable.zip(collection.map { $0.asObservable() }, resultSelector: resultSelector)
        return PrimitiveSequence<Trait, Result>(raw: raw)
    }
    
    /**
     Merges the specified observable sequences into one observable sequence all of the observable sequences have produced an element at a corresponding index.
     
     - returns: An observable sequence containing the result of combining elements of the sources.
     */
    public static func zip<Collection: Swift.Collection>(_ collection: Collection) -> PrimitiveSequence<Trait, [Element]> where Collection.Element == PrimitiveSequence<Trait, Element> {
        
        if collection.isEmpty {
            return PrimitiveSequence<Trait, [Element]>(raw: .just([]))
        }
        
        let raw = Observable.zip(collection.map { $0.asObservable() })
        return PrimitiveSequence(raw: raw)
    }

    /**
     Continues an observable sequence that is terminated by an error with a single element.

     - seealso: [catch operator on reactivex.io](http://reactivex.io/documentation/operators/catch.html)

     - parameter element: Last element in an observable sequence in case error occurs.
     - returns: An observable sequence containing the source sequence's elements, followed by the `element` in case an error occurred.
     */
    public func catchAndReturn(_ element: Element)
        -> PrimitiveSequence<Trait, Element> {
        PrimitiveSequence(raw: self.primitiveSequence.source.catchAndReturn(element))
    }

    /**
     Continues an observable sequence that is terminated by an error with a single element.

     - seealso: [catch operator on reactivex.io](http://reactivex.io/documentation/operators/catch.html)

     - parameter element: Last element in an observable sequence in case error occurs.
     - returns: An observable sequence containing the source sequence's elements, followed by the `element` in case an error occurred.
     */
    @available(*, deprecated, renamed: "catchAndReturn(_:)")
    public func catchErrorJustReturn(_ element: Element)
        -> PrimitiveSequence<Trait, Element> {
        catchAndReturn(element)
    }

    /// Converts `self` to `Maybe` trait.
    ///
    /// - returns: Maybe trait that represents `self`.
    public func asMaybe() -> Maybe<Element> {
        Maybe(raw: self.primitiveSequence.source)
    }

    /// Converts `self` to `Completable` trait, ignoring its emitted value if
    /// one exists.
    /// 
    /// - returns: Completable trait that represents `self`.
    public func asCompletable() -> Completable {
        self.primitiveSequence.source.ignoreElements().asCompletable()
    }
}
