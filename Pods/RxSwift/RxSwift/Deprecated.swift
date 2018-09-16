//
//  Deprecated.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/5/17.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

extension Observable {
    /**
     Converts a optional to an observable sequence.
     
     - seealso: [from operator on reactivex.io](http://reactivex.io/documentation/operators/from.html)
     
     - parameter optional: Optional element in the resulting observable sequence.
     - returns: An observable sequence containing the wrapped value or not from given optional.
     */
    @available(*, deprecated, message: "Implicit conversions from any type to optional type are allowed and that is causing issues with `from` operator overloading.", renamed: "from(optional:)")
    public static func from(_ optional: E?) -> Observable<E> {
        return Observable.from(optional: optional)
    }

    /**
     Converts a optional to an observable sequence.

     - seealso: [from operator on reactivex.io](http://reactivex.io/documentation/operators/from.html)

     - parameter optional: Optional element in the resulting observable sequence.
     - parameter: Scheduler to send the optional element on.
     - returns: An observable sequence containing the wrapped value or not from given optional.
     */
    @available(*, deprecated, message: "Implicit conversions from any type to optional type are allowed and that is causing issues with `from` operator overloading.", renamed: "from(optional:scheduler:)")
    public static func from(_ optional: E?, scheduler: ImmediateSchedulerType) -> Observable<E> {
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
    public func mapWithIndex<R>(_ selector: @escaping (E, Int) throws -> R)
        -> Observable<R> {
        return enumerated().map { try selector($0.element, $0.index) }
    }


    /**

     Projects each element of an observable sequence to an observable sequence by incorporating the element's index and merges the resulting observable sequences into one observable sequence.

     - seealso: [flatMap operator on reactivex.io](http://reactivex.io/documentation/operators/flatmap.html)

     - parameter selector: A transform function to apply to each element; the second parameter of the function represents the index of the source element.
     - returns: An observable sequence whose elements are the result of invoking the one-to-many transform function on each element of the input sequence.
     */
    @available(*, deprecated, message: "Please use enumerated().flatMap()")
    public func flatMapWithIndex<O: ObservableConvertibleType>(_ selector: @escaping (E, Int) throws -> O)
        -> Observable<O.E> {
        return enumerated().flatMap { try selector($0.element, $0.index) }
    }

    /**

     Bypasses elements in an observable sequence as long as a specified condition is true and then returns the remaining elements.
     The element's index is used in the logic of the predicate function.

     - seealso: [skipWhile operator on reactivex.io](http://reactivex.io/documentation/operators/skipwhile.html)

     - parameter predicate: A function to test each element for a condition; the second parameter of the function represents the index of the source element.
     - returns: An observable sequence that contains the elements from the input sequence starting at the first element in the linear series that does not pass the test specified by predicate.
     */
    @available(*, deprecated, message: "Please use enumerated().skipWhile().map()")
    public func skipWhileWithIndex(_ predicate: @escaping (E, Int) throws -> Bool) -> Observable<E> {
        return enumerated().skipWhile { try predicate($0.element, $0.index) }.map { $0.element }
    }


    /**

     Returns elements from an observable sequence as long as a specified condition is true.

     The element's index is used in the logic of the predicate function.

     - seealso: [takeWhile operator on reactivex.io](http://reactivex.io/documentation/operators/takewhile.html)

     - parameter predicate: A function to test each element for a condition; the second parameter of the function represents the index of the source element.
     - returns: An observable sequence that contains the elements from the input sequence that occur before the element at which the test no longer passes.
     */
    @available(*, deprecated, message: "Please use enumerated().takeWhile().map()")
    public func takeWhileWithIndex(_ predicate: @escaping (E, Int) throws -> Bool) -> Observable<E> {
        return enumerated().takeWhile { try predicate($0.element, $0.index) }.map { $0.element }
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
        disposed(by: bag)
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
        -> Observable<E> {
        return share(replay: 1, scope: .whileConnected)
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
        -> Observable<E> {
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
public final class Variable<Element> {

    public typealias E = Element

    private let _subject: BehaviorSubject<Element>

    private var _lock = SpinLock()

    // state
    private var _value: E

    #if DEBUG
    fileprivate let _synchronizationTracker = SynchronizationTracker()
    #endif

    /// Gets or sets current value of variable.
    ///
    /// Whenever a new value is set, all the observers are notified of the change.
    ///
    /// Even if the newly set value is same as the old value, observers are still notified for change.
    public var value: E {
        get {
            _lock.lock(); defer { _lock.unlock() }
            return _value
        }
        set(newValue) {
            #if DEBUG
                _synchronizationTracker.register(synchronizationErrorMessage: .variable)
                defer { _synchronizationTracker.unregister() }
            #endif
            _lock.lock()
            _value = newValue
            _lock.unlock()

            _subject.on(.next(newValue))
        }
    }

    /// Initializes variable with initial value.
    ///
    /// - parameter value: Initial variable value.
    public init(_ value: Element) {
        #if DEBUG
            DeprecationWarner.warnIfNeeded(.variable)
        #endif

        _value = value
        _subject = BehaviorSubject(value: value)
    }

    /// - returns: Canonical interface for push style sequence
    public func asObservable() -> Observable<E> {
        return _subject
    }

    deinit {
        _subject.on(.completed)
    }
}
