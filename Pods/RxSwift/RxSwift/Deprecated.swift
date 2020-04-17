//
//  Deprecated.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/5/17.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

import Foundation

extension Observable {
    /**
     Converts a optional to an observable sequence.
     
     - seealso: [from operator on reactivex.io](http://reactivex.io/documentation/operators/from.html)
     
     - parameter optional: Optional element in the resulting observable sequence.
     - returns: An observable sequence containing the wrapped value or not from given optional.
     */
    @available(*, deprecated, message: "Implicit conversions from any type to optional type are allowed and that is causing issues with `from` operator overloading.", renamed: "from(optional:)")
    public static func from(_ optional: Element?) -> Observable<Element> {
        return Observable.from(optional: optional)
    }

    /**
     Converts a optional to an observable sequence.

     - seealso: [from operator on reactivex.io](http://reactivex.io/documentation/operators/from.html)

     - parameter optional: Optional element in the resulting observable sequence.
     - parameter scheduler: Scheduler to send the optional element on.
     - returns: An observable sequence containing the wrapped value or not from given optional.
     */
    @available(*, deprecated, message: "Implicit conversions from any type to optional type are allowed and that is causing issues with `from` operator overloading.", renamed: "from(optional:scheduler:)")
    public static func from(_ optional: Element?, scheduler: ImmediateSchedulerType) -> Observable<Element> {
        return Observable.from(optional: optional, scheduler: scheduler)
    }
}

extension ObservableType {
    /**

    Projects each element of an observable sequence into a new form by incorporating the element's index.

     - seealso: [map operator on reactivex.io](http://reactivex.io/documentation/operators/map.html)

     - parameter selector: A transform function to apply to each source element; the second parameter of the function represents the index of the source element.
     - returns: An observable sequence whose elements are the result of invoking the transform function on each element of source.
     */
    @available(*, deprecated, message: "Please use enumerated().map()")
    public func mapWithIndex<Result>(_ selector: @escaping (Element, Int) throws -> Result)
        -> Observable<Result> {
        return self.enumerated().map { try selector($0.element, $0.index) }
    }


    /**

     Projects each element of an observable sequence to an observable sequence by incorporating the element's index and merges the resulting observable sequences into one observable sequence.

     - seealso: [flatMap operator on reactivex.io](http://reactivex.io/documentation/operators/flatmap.html)

     - parameter selector: A transform function to apply to each element; the second parameter of the function represents the index of the source element.
     - returns: An observable sequence whose elements are the result of invoking the one-to-many transform function on each element of the input sequence.
     */
    @available(*, deprecated, message: "Please use enumerated().flatMap()")
    public func flatMapWithIndex<Source: ObservableConvertibleType>(_ selector: @escaping (Element, Int) throws -> Source)
        -> Observable<Source.Element> {
        return self.enumerated().flatMap { try selector($0.element, $0.index) }
    }

    /**

     Bypasses elements in an observable sequence as long as a specified condition is true and then returns the remaining elements.
     The element's index is used in the logic of the predicate function.

     - seealso: [skipWhile operator on reactivex.io](http://reactivex.io/documentation/operators/skipwhile.html)

     - parameter predicate: A function to test each element for a condition; the second parameter of the function represents the index of the source element.
     - returns: An observable sequence that contains the elements from the input sequence starting at the first element in the linear series that does not pass the test specified by predicate.
     */
    @available(*, deprecated, message: "Please use enumerated().skipWhile().map()")
    public func skipWhileWithIndex(_ predicate: @escaping (Element, Int) throws -> Bool) -> Observable<Element> {
        return self.enumerated().skipWhile { try predicate($0.element, $0.index) }.map { $0.element }
    }


    /**

     Returns elements from an observable sequence as long as a specified condition is true.

     The element's index is used in the logic of the predicate function.

     - seealso: [takeWhile operator on reactivex.io](http://reactivex.io/documentation/operators/takewhile.html)

     - parameter predicate: A function to test each element for a condition; the second parameter of the function represents the index of the source element.
     - returns: An observable sequence that contains the elements from the input sequence that occur before the element at which the test no longer passes.
     */
    @available(*, deprecated, message: "Please use enumerated().takeWhile().map()")
    public func takeWhileWithIndex(_ predicate: @escaping (Element, Int) throws -> Bool) -> Observable<Element> {
        return self.enumerated().takeWhile { try predicate($0.element, $0.index) }.map { $0.element }
    }
}

extension Disposable {
    /// Deprecated in favor of `disposed(by:)`
    ///
    ///
    /// Adds `self` to `bag`.
    ///
    /// - parameter bag: `DisposeBag` to add `self` to.
    @available(*, deprecated, message: "use disposed(by:) instead", renamed: "disposed(by:)")
    public func addDisposableTo(_ bag: DisposeBag) {
        self.disposed(by: bag)
    }
}


extension ObservableType {

    /**
     Returns an observable sequence that shares a single subscription to the underlying sequence, and immediately upon subscription replays latest element in buffer.

     This operator is a specialization of replay which creates a subscription when the number of observers goes from zero to one, then shares that subscription with all subsequent observers until the number of observers returns to zero, at which point the subscription is disposed.

     - seealso: [shareReplay operator on reactivex.io](http://reactivex.io/documentation/operators/replay.html)

     - returns: An observable sequence that contains the elements of a sequence produced by multicasting the source sequence.
     */
    @available(*, deprecated, message: "use share(replay: 1) instead", renamed: "share(replay:)")
    public func shareReplayLatestWhileConnected()
        -> Observable<Element> {
        return self.share(replay: 1, scope: .whileConnected)
    }
}


extension ObservableType {

    /**
     Returns an observable sequence that shares a single subscription to the underlying sequence, and immediately upon subscription replays maximum number of elements in buffer.

     This operator is a specialization of replay which creates a subscription when the number of observers goes from zero to one, then shares that subscription with all subsequent observers until the number of observers returns to zero, at which point the subscription is disposed.

     - seealso: [shareReplay operator on reactivex.io](http://reactivex.io/documentation/operators/replay.html)

     - parameter bufferSize: Maximum element count of the replay buffer.
     - returns: An observable sequence that contains the elements of a sequence produced by multicasting the source sequence.
     */
    @available(*, deprecated, message: "Suggested replacement is `share(replay: 1)`. In case old 3.x behavior of `shareReplay` is required please use `share(replay: 1, scope: .forever)` instead.", renamed: "share(replay:)")
    public func shareReplay(_ bufferSize: Int)
        -> Observable<Element> {
        return self.share(replay: bufferSize, scope: .forever)
    }
}

/// Variable is a wrapper for `BehaviorSubject`.
///
/// Unlike `BehaviorSubject` it can't terminate with error, and when variable is deallocated
/// it will complete its observable sequence (`asObservable`).
///
/// **This concept will be deprecated from RxSwift but offical migration path hasn't been decided yet.**
/// https://github.com/ReactiveX/RxSwift/issues/1501
///
/// Current recommended replacement for this API is `RxCocoa.BehaviorRelay` because:
/// * `Variable` isn't a standard cross platform concept, hence it's out of place in RxSwift target.
/// * It doesn't have a counterpart for handling events (`PublishRelay`). It models state only.
/// * It doesn't have a consistent naming with *Relay or other Rx concepts.
/// * It has an inconsistent memory management model compared to other parts of RxSwift (completes on `deinit`).
///
/// Once plans are finalized, official availability attribute will be added in one of upcoming versions.
@available(*, deprecated, message: "Variable is deprecated. Please use `BehaviorRelay` as a replacement.")
public final class Variable<Element> {
    private let _subject: BehaviorSubject<Element>

    private var _lock = SpinLock()

    // state
    private var _value: Element

    #if DEBUG
    private let _synchronizationTracker = SynchronizationTracker()
    #endif

    /// Gets or sets current value of variable.
    ///
    /// Whenever a new value is set, all the observers are notified of the change.
    ///
    /// Even if the newly set value is same as the old value, observers are still notified for change.
    public var value: Element {
        get {
            self._lock.lock(); defer { self._lock.unlock() }
            return self._value
        }
        set(newValue) {
            #if DEBUG
                self._synchronizationTracker.register(synchronizationErrorMessage: .variable)
                defer { self._synchronizationTracker.unregister() }
            #endif
            self._lock.lock()
            self._value = newValue
            self._lock.unlock()

            self._subject.on(.next(newValue))
        }
    }

    /// Initializes variable with initial value.
    ///
    /// - parameter value: Initial variable value.
    public init(_ value: Element) {
        self._value = value
        self._subject = BehaviorSubject(value: value)
    }

    /// - returns: Canonical interface for push style sequence
    public func asObservable() -> Observable<Element> {
        return self._subject
    }

    deinit {
        self._subject.on(.completed)
    }
}

extension ObservableType {
    /**
     Returns an observable sequence by the source observable sequence shifted forward in time by a specified delay. Error events from the source observable sequence are not delayed.
    
     - seealso: [delay operator on reactivex.io](http://reactivex.io/documentation/operators/delay.html)
    
     - parameter dueTime: Relative time shift of the source by.
     - parameter scheduler: Scheduler to run the subscription delay timer on.
     - returns: the source Observable shifted in time by the specified delay.
     */
    @available(*, deprecated, message: "Use DispatchTimeInterval overload instead.", renamed: "delay(_:scheduler:)")
    public func delay(_ dueTime: Foundation.TimeInterval, scheduler: SchedulerType)
        -> Observable<Element> {
        return self.delay(.milliseconds(Int(dueTime * 1000.0)), scheduler: scheduler)
    }
}

extension ObservableType {
    
    /**
     Applies a timeout policy for each element in the observable sequence. If the next element isn't received within the specified timeout duration starting from its predecessor, a TimeoutError is propagated to the observer.
     
     - seealso: [timeout operator on reactivex.io](http://reactivex.io/documentation/operators/timeout.html)
     
     - parameter dueTime: Maximum duration between values before a timeout occurs.
     - parameter scheduler: Scheduler to run the timeout timer on.
     - returns: An observable sequence with a `RxError.timeout` in case of a timeout.
     */
    @available(*, deprecated, message: "Use DispatchTimeInterval overload instead.", renamed: "timeout(_:scheduler:)")
    public func timeout(_ dueTime: Foundation.TimeInterval, scheduler: SchedulerType)
        -> Observable<Element> {
        return timeout(.milliseconds(Int(dueTime * 1000.0)), scheduler: scheduler)
    }
    
    /**
     Applies a timeout policy for each element in the observable sequence, using the specified scheduler to run timeout timers. If the next element isn't received within the specified timeout duration starting from its predecessor, the other observable sequence is used to produce future messages from that point on.
     
     - seealso: [timeout operator on reactivex.io](http://reactivex.io/documentation/operators/timeout.html)
     
     - parameter dueTime: Maximum duration between values before a timeout occurs.
     - parameter other: Sequence to return in case of a timeout.
     - parameter scheduler: Scheduler to run the timeout timer on.
     - returns: The source sequence switching to the other sequence in case of a timeout.
     */
    @available(*, deprecated, message: "Use DispatchTimeInterval overload instead.", renamed: "timeout(_:other:scheduler:)")
    public func timeout<OtherSource: ObservableConvertibleType>(_ dueTime: Foundation.TimeInterval, other: OtherSource, scheduler: SchedulerType)
        -> Observable<Element> where Element == OtherSource.Element {
        return timeout(.milliseconds(Int(dueTime * 1000.0)), other: other, scheduler: scheduler)
    }
}

extension ObservableType {
    
    /**
     Skips elements for the specified duration from the start of the observable source sequence, using the specified scheduler to run timers.
     
     - seealso: [skip operator on reactivex.io](http://reactivex.io/documentation/operators/skip.html)
     
     - parameter duration: Duration for skipping elements from the start of the sequence.
     - parameter scheduler: Scheduler to run the timer on.
     - returns: An observable sequence with the elements skipped during the specified duration from the start of the source sequence.
     */
    @available(*, deprecated, message: "Use DispatchTimeInterval overload instead.", renamed: "skip(_:scheduler:)")
    public func skip(_ duration: Foundation.TimeInterval, scheduler: SchedulerType)
        -> Observable<Element> {
        return skip(.milliseconds(Int(duration * 1000.0)), scheduler: scheduler)
    }
}

extension ObservableType where Element : RxAbstractInteger {
    /**
     Returns an observable sequence that produces a value after each period, using the specified scheduler to run timers and to send out observer messages.
     
     - seealso: [interval operator on reactivex.io](http://reactivex.io/documentation/operators/interval.html)
     
     - parameter period: Period for producing the values in the resulting sequence.
     - parameter scheduler: Scheduler to run the timer on.
     - returns: An observable sequence that produces a value after each period.
     */
    @available(*, deprecated, message: "Use DispatchTimeInterval overload instead.", renamed: "interval(_:scheduler:)")
    public static func interval(_ period: Foundation.TimeInterval, scheduler: SchedulerType)
        -> Observable<Element> {
        return interval(.milliseconds(Int(period * 1000.0)), scheduler: scheduler)
    }
}

extension ObservableType where Element: RxAbstractInteger {
    /**
     Returns an observable sequence that periodically produces a value after the specified initial relative due time has elapsed, using the specified scheduler to run timers.
     
     - seealso: [timer operator on reactivex.io](http://reactivex.io/documentation/operators/timer.html)
     
     - parameter dueTime: Relative time at which to produce the first value.
     - parameter period: Period to produce subsequent values.
     - parameter scheduler: Scheduler to run timers on.
     - returns: An observable sequence that produces a value after due time has elapsed and then each period.
     */
    @available(*, deprecated, message: "Use DispatchTimeInterval overload instead.", renamed: "timer(_:period:scheduler:)")
    public static func timer(_ dueTime: Foundation.TimeInterval, period: Foundation.TimeInterval? = nil, scheduler: SchedulerType)
        -> Observable<Element> {
        return timer(.milliseconds(Int(dueTime * 1000.0)), period: period.map { .milliseconds(Int($0 * 1000.0)) }, scheduler: scheduler)
    }
}

extension ObservableType {
    
    /**
     Returns an Observable that emits the first and the latest item emitted by the source Observable during sequential time windows of a specified duration.
     
     This operator makes sure that no two elements are emitted in less then dueTime.
     
     - seealso: [debounce operator on reactivex.io](http://reactivex.io/documentation/operators/debounce.html)
     
     - parameter dueTime: Throttling duration for each element.
     - parameter latest: Should latest element received in a dueTime wide time window since last element emission be emitted.
     - parameter scheduler: Scheduler to run the throttle timers on.
     - returns: The throttled sequence.
     */
    @available(*, deprecated, message: "Use DispatchTimeInterval overload instead.", renamed: "throttle(_:latest:scheduler:)")
    public func throttle(_ dueTime: Foundation.TimeInterval, latest: Bool = true, scheduler: SchedulerType)
        -> Observable<Element> {
        return throttle(.milliseconds(Int(dueTime * 1000.0)), latest: latest, scheduler: scheduler)
    }
}

extension ObservableType {
    
    /**
     Takes elements for the specified duration from the start of the observable source sequence, using the specified scheduler to run timers.
     
     - seealso: [take operator on reactivex.io](http://reactivex.io/documentation/operators/take.html)
     
     - parameter duration: Duration for taking elements from the start of the sequence.
     - parameter scheduler: Scheduler to run the timer on.
     - returns: An observable sequence with the elements taken during the specified duration from the start of the source sequence.
     */
    @available(*, deprecated, message: "Use DispatchTimeInterval overload instead.", renamed: "take(_:scheduler:)")
    public func take(_ duration: Foundation.TimeInterval, scheduler: SchedulerType)
        -> Observable<Element> {
        return take(.milliseconds(Int(duration * 1000.0)), scheduler: scheduler)
    }
}


extension ObservableType {
    
    /**
     Time shifts the observable sequence by delaying the subscription with the specified relative time duration, using the specified scheduler to run timers.
     
     - seealso: [delay operator on reactivex.io](http://reactivex.io/documentation/operators/delay.html)
     
     - parameter dueTime: Relative time shift of the subscription.
     - parameter scheduler: Scheduler to run the subscription delay timer on.
     - returns: Time-shifted sequence.
     */
    @available(*, deprecated, message: "Use DispatchTimeInterval overload instead.", renamed: "delaySubscription(_:scheduler:)")
    public func delaySubscription(_ dueTime: Foundation.TimeInterval, scheduler: SchedulerType)
        -> Observable<Element> {
        return delaySubscription(.milliseconds(Int(dueTime * 1000.0)), scheduler: scheduler)
    }
}

extension ObservableType {
    
    /**
     Projects each element of an observable sequence into a window that is completed when either it’s full or a given amount of time has elapsed.
     
     - seealso: [window operator on reactivex.io](http://reactivex.io/documentation/operators/window.html)
     
     - parameter timeSpan: Maximum time length of a window.
     - parameter count: Maximum element count of a window.
     - parameter scheduler: Scheduler to run windowing timers on.
     - returns: An observable sequence of windows (instances of `Observable`).
     */
    @available(*, deprecated, message: "Use DispatchTimeInterval overload instead.", renamed: "window(_:)")
    public func window(timeSpan: Foundation.TimeInterval, count: Int, scheduler: SchedulerType)
        -> Observable<Observable<Element>> {
            return window(timeSpan: .milliseconds(Int(timeSpan * 1000.0)), count: count, scheduler: scheduler)
    }
}


extension PrimitiveSequence {
    /**
     Returns an observable sequence by the source observable sequence shifted forward in time by a specified delay. Error events from the source observable sequence are not delayed.
     
     - seealso: [delay operator on reactivex.io](http://reactivex.io/documentation/operators/delay.html)
     
     - parameter dueTime: Relative time shift of the source by.
     - parameter scheduler: Scheduler to run the subscription delay timer on.
     - returns: the source Observable shifted in time by the specified delay.
     */
    @available(*, deprecated, message: "Use DispatchTimeInterval overload instead.", renamed: "delay(_:scheduler:)")
    public func delay(_ dueTime: Foundation.TimeInterval, scheduler: SchedulerType)
        -> PrimitiveSequence<Trait, Element> {
        return delay(.milliseconds(Int(dueTime * 1000.0)), scheduler: scheduler)
    }
            
    /**
     Time shifts the observable sequence by delaying the subscription with the specified relative time duration, using the specified scheduler to run timers.
     
     - seealso: [delay operator on reactivex.io](http://reactivex.io/documentation/operators/delay.html)
     
     - parameter dueTime: Relative time shift of the subscription.
     - parameter scheduler: Scheduler to run the subscription delay timer on.
     - returns: Time-shifted sequence.
     */
    @available(*, deprecated, message: "Use DispatchTimeInterval overload instead.", renamed: "delaySubscription(_:scheduler:)")
    public func delaySubscription(_ dueTime: Foundation.TimeInterval, scheduler: SchedulerType)
        -> PrimitiveSequence<Trait, Element> {
        return delaySubscription(.milliseconds(Int(dueTime * 1000.0)), scheduler: scheduler)
    }
    
    /**
     Applies a timeout policy for each element in the observable sequence. If the next element isn't received within the specified timeout duration starting from its predecessor, a TimeoutError is propagated to the observer.
     
     - seealso: [timeout operator on reactivex.io](http://reactivex.io/documentation/operators/timeout.html)
     
     - parameter dueTime: Maximum duration between values before a timeout occurs.
     - parameter scheduler: Scheduler to run the timeout timer on.
     - returns: An observable sequence with a `RxError.timeout` in case of a timeout.
     */
    @available(*, deprecated, message: "Use DispatchTimeInterval overload instead.", renamed: "timeout(_:scheduler:)")
    public func timeout(_ dueTime: Foundation.TimeInterval, scheduler: SchedulerType)
        -> PrimitiveSequence<Trait, Element> {
        return timeout(.milliseconds(Int(dueTime * 1000.0)), scheduler: scheduler)
    }
    
    /**
     Applies a timeout policy for each element in the observable sequence, using the specified scheduler to run timeout timers. If the next element isn't received within the specified timeout duration starting from its predecessor, the other observable sequence is used to produce future messages from that point on.
     
     - seealso: [timeout operator on reactivex.io](http://reactivex.io/documentation/operators/timeout.html)
     
     - parameter dueTime: Maximum duration between values before a timeout occurs.
     - parameter other: Sequence to return in case of a timeout.
     - parameter scheduler: Scheduler to run the timeout timer on.
     - returns: The source sequence switching to the other sequence in case of a timeout.
     */
    @available(*, deprecated, message: "Use DispatchTimeInterval overload instead.", renamed: "timeout(_:other:scheduler:)")
    public func timeout(_ dueTime: Foundation.TimeInterval,
                        other: PrimitiveSequence<Trait, Element>,
                        scheduler: SchedulerType) -> PrimitiveSequence<Trait, Element> {
        return timeout(.milliseconds(Int(dueTime * 1000.0)), other: other, scheduler: scheduler)
    }
}

extension PrimitiveSequenceType where Trait == SingleTrait {

    /**
     Invokes an action for each event in the observable sequence, and propagates all observer messages through the result sequence.
     
     - seealso: [do operator on reactivex.io](http://reactivex.io/documentation/operators/do.html)
     
     - parameter onNext: Action to invoke for each element in the observable sequence.
     - parameter onError: Action to invoke upon errored termination of the observable sequence.
     - parameter onSubscribe: Action to invoke before subscribing to source observable sequence.
     - parameter onSubscribed: Action to invoke after subscribing to source observable sequence.
     - parameter onDispose: Action to invoke after subscription to source observable has been disposed for any reason. It can be either because sequence terminates for some reason or observer subscription being disposed.
     - returns: The source sequence with the side-effecting behavior applied.
     */
    @available(*, deprecated, renamed: "do(onSuccess:onError:onSubscribe:onSubscribed:onDispose:)")
    public func `do`(onNext: ((Element) throws -> Void)?,
                     onError: ((Swift.Error) throws -> Void)? = nil,
                     onSubscribe: (() -> Void)? = nil,
                     onSubscribed: (() -> Void)? = nil,
                     onDispose: (() -> Void)? = nil)
        -> Single<Element> {
        return self.`do`(
            onSuccess: onNext,
            onError: onError,
            onSubscribe: onSubscribe,
            onSubscribed: onSubscribed,
            onDispose: onDispose
        )
    }
}

extension ObservableType {
    /**
     Projects each element of an observable sequence into a buffer that's sent out when either it's full or a given amount of time has elapsed, using the specified scheduler to run timers.
     
     A useful real-world analogy of this overload is the behavior of a ferry leaving the dock when all seats are taken, or at the scheduled time of departure, whichever event occurs first.
     
     - seealso: [buffer operator on reactivex.io](http://reactivex.io/documentation/operators/buffer.html)
     
     - parameter timeSpan: Maximum time length of a buffer.
     - parameter count: Maximum element count of a buffer.
     - parameter scheduler: Scheduler to run buffering timers on.
     - returns: An observable sequence of buffers.
     */
    @available(*, deprecated, message: "Use DispatchTimeInterval overload instead.", renamed: "buffer(timeSpan:count:scheduler:)")
    public func buffer(timeSpan: Foundation.TimeInterval, count: Int, scheduler: SchedulerType)
        -> Observable<[Element]> {
        return buffer(timeSpan: .milliseconds(Int(timeSpan * 1000.0)), count: count, scheduler: scheduler)
    }
}

extension PrimitiveSequenceType where Element: RxAbstractInteger
{
    /**
     Returns an observable sequence that periodically produces a value after the specified initial relative due time has elapsed, using the specified scheduler to run timers.
     
     - seealso: [timer operator on reactivex.io](http://reactivex.io/documentation/operators/timer.html)
     
     - parameter dueTime: Relative time at which to produce the first value.
     - parameter scheduler: Scheduler to run timers on.
     - returns: An observable sequence that produces a value after due time has elapsed and then each period.
     */
    @available(*, deprecated, message: "Use DispatchTimeInterval overload instead.", renamed: "timer(_:scheduler:)")
    public static func timer(_ dueTime: Foundation.TimeInterval, scheduler: SchedulerType)
        -> PrimitiveSequence<Trait, Element>  {
        return timer(.milliseconds(Int(dueTime * 1000.0)), scheduler: scheduler)
    }
}

extension Completable {
    /**
     Merges the completion of all Completables from a collection into a single Completable.

     - seealso: [merge operator on reactivex.io](http://reactivex.io/documentation/operators/merge.html)

     - parameter sources: Collection of Completables to merge.
     - returns: A Completable that merges the completion of all Completables.
     */
    @available(*, deprecated, message: "Use Completable.zip instead.", renamed: "zip")
    public static func merge<Collection: Swift.Collection>(_ sources: Collection) -> Completable
           where Collection.Element == Completable {
        return zip(sources)
    }

    /**
     Merges the completion of all Completables from an array into a single Completable.

     - seealso: [merge operator on reactivex.io](http://reactivex.io/documentation/operators/merge.html)

     - parameter sources: Array of observable sequences to merge.
     - returns: A Completable that merges the completion of all Completables.
     */
    @available(*, deprecated, message: "Use Completable.zip instead.", renamed: "zip")
    public static func merge(_ sources: [Completable]) -> Completable {
        return zip(sources)
    }

    /**
     Merges the completion of all Completables into a single Completable.

     - seealso: [merge operator on reactivex.io](http://reactivex.io/documentation/operators/merge.html)

     - parameter sources: Collection of observable sequences to merge.
     - returns: The observable sequence that merges the elements of the observable sequences.
     */
    @available(*, deprecated, message: "Use Completable.zip instead.", renamed: "zip")
    public static func merge(_ sources: Completable...) -> Completable {
        return zip(sources)
    }
}
