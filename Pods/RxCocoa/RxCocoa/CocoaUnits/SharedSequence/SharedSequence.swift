//
//  SharedSequence.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 8/27/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation
#if !RX_NO_MODULE
    import RxSwift
#endif

/**
    Unit that represents observable sequence that shares computation resources with following properties:

    - it never fails
    - it delivers events on `SharingStrategy.scheduler`
    - sharing strategy is customizable using `SharingStrategy.share` behavior

    `SharedSequence<Element>` can be considered a builder pattern for observable sequences that share computation resources.

    To find out more about units and how to use them, please visit `Documentation/Units.md`.
*/
public struct SharedSequence<S: SharingStrategyProtocol, Element> : SharedSequenceConvertibleType {
    public typealias E = Element
    public typealias SharingStrategy = S

    let _source: Observable<E>

    init(_ source: Observable<E>) {
        self._source = S.share(source)
    }

    init(raw: Observable<E>) {
        self._source = raw
    }

    #if EXPANDABLE_SHARED_SEQUENCE
    /**
     This method is extension hook in case this unit needs to extended from outside the library.
     
     By defining `EXPANDABLE_SHARED_SEQUENCE` one agrees that it's up to him to ensure shared sequence
     properties are preserved after extension.
    */
    public static func createUnsafe<O: ObservableType>(source: O) -> SharedSequence<S, O.E> {
        return SharedSequence<S, O.E>(raw: source.asObservable())
    }
    #endif

    /**
    - returns: Built observable sequence.
    */
    public func asObservable() -> Observable<E> {
        return _source
    }

    /**
    - returns: `self`
    */
    public func asSharedSequence() -> SharedSequence<SharingStrategy, E> {
        return self
    }
}

/**
 Different `SharedSequence` sharing strategies must conform to this protocol.
 */
public protocol SharingStrategyProtocol {
    /**
     Scheduled on which all sequence events will be delivered.
    */
    static var scheduler: SchedulerType { get }

    /**
     Computation resources sharing strategy for multiple sequence observers.
     
     E.g. One can choose `shareReplayWhenConnected`, `shareReplay` or `share`
     as sequence event sharing strategies, but also do something more exotic, like
     implementing promises or lazy loading chains.
    */
    static func share<E>(_ source: Observable<E>) -> Observable<E>
}

/**
A type that can be converted to `SharedSequence`.
*/
public protocol SharedSequenceConvertibleType : ObservableConvertibleType {
    associatedtype SharingStrategy: SharingStrategyProtocol

    /**
    Converts self to `SharedSequence`.
    */
    func asSharedSequence() -> SharedSequence<SharingStrategy, E>
}

extension SharedSequenceConvertibleType {
    public func asObservable() -> Observable<E> {
        return asSharedSequence().asObservable()
    }
}


extension SharedSequence {

    /**
    Returns an empty observable sequence, using the specified scheduler to send out the single `Completed` message.

    - returns: An observable sequence with no elements.
    */
    public static func empty() -> SharedSequence<S, E> {
        return SharedSequence(Observable.empty().subscribeOn(S.scheduler))
    }

    /**
    Returns a non-terminating observable sequence, which can be used to denote an infinite duration.

    - returns: An observable sequence whose observers will never get called.
    */
    public static func never() -> SharedSequence<S, E> {
        return SharedSequence(Observable.never())
    }

    /**
    Returns an observable sequence that contains a single element.

    - parameter element: Single element in the resulting observable sequence.
    - returns: An observable sequence containing the single specified element.
    */
    public static func just(_ element: E) -> SharedSequence<S, E> {
        return SharedSequence(Observable.just(element).subscribeOn(S.scheduler))
    }

    /**
     Returns an observable sequence that invokes the specified factory function whenever a new observer subscribes.

     - parameter observableFactory: Observable factory function to invoke for each observer that subscribes to the resulting sequence.
     - returns: An observable sequence whose observers trigger an invocation of the given observable factory function.
     */
    public static func deferred(_ observableFactory: @escaping () -> SharedSequence<S, E>)
        -> SharedSequence<S, E> {
        return SharedSequence(Observable.deferred { observableFactory().asObservable() })
    }

    /**
    This method creates a new Observable instance with a variable number of elements.

    - seealso: [from operator on reactivex.io](http://reactivex.io/documentation/operators/from.html)

    - parameter elements: Elements to generate.
    - returns: The observable sequence whose elements are pulled from the given arguments.
    */
    public static func of(_ elements: E ...) -> SharedSequence<S, E> {
        let source = Observable.from(elements, scheduler: S.scheduler)
        return SharedSequence(raw: source)
    }
}

extension SharedSequence where Element : SignedInteger {
    /**
     Returns an observable sequence that produces a value after each period, using the specified scheduler to run timers and to send out observer messages.

     - seealso: [interval operator on reactivex.io](http://reactivex.io/documentation/operators/interval.html)

     - parameter period: Period for producing the values in the resulting sequence.
     - returns: An observable sequence that produces a value after each period.
     */
    public static func interval(_ period: RxTimeInterval)
        -> SharedSequence<S, E> {
        return SharedSequence(Observable.interval(period, scheduler: S.scheduler))
    }
}

// MARK: timer

extension SharedSequence where Element: SignedInteger {
    /**
     Returns an observable sequence that periodically produces a value after the specified initial relative due time has elapsed, using the specified scheduler to run timers.

     - seealso: [timer operator on reactivex.io](http://reactivex.io/documentation/operators/timer.html)

     - parameter dueTime: Relative time at which to produce the first value.
     - parameter period: Period to produce subsequent values.
     - returns: An observable sequence that produces a value after due time has elapsed and then each period.
     */
    public static func timer(_ dueTime: RxTimeInterval, period: RxTimeInterval)
        -> SharedSequence<S, E> {
        return SharedSequence(Observable.timer(dueTime, period: period, scheduler: S.scheduler))
    }
}

