//
//  Observable+Time.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/22/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

// MARK: throttle
extension ObservableType {
    
    /**
    Returns an Observable that emits the first and the latest item emitted by the source Observable during sequential time windows of a specified duration.
    
    This operator makes sure that no two elements are emitted in less then dueTime.
     
    - seealso: [debounce operator on reactivex.io](http://reactivex.io/documentation/operators/debounce.html)
    
    - parameter dueTime: Throttling duration for each element.
    - parameter latest: Should latest element received in a dueTime wide time window since last element emission be emitted.
    - parameter scheduler: Scheduler to run the throttle timers and send events on.
    - returns: The throttled sequence.
    */
    public func throttle(_ dueTime: RxTimeInterval, latest: Bool = true, scheduler: SchedulerType)
        -> Observable<E> {
        return Throttle(source: self.asObservable(), dueTime: dueTime, latest: latest, scheduler: scheduler)
    }

    /**
    Ignores elements from an observable sequence which are followed by another element within a specified relative time duration, using the specified scheduler to run throttling timers.
    
    - seealso: [debounce operator on reactivex.io](http://reactivex.io/documentation/operators/debounce.html)
    
    - parameter dueTime: Throttling duration for each element.
    - parameter scheduler: Scheduler to run the throttle timers and send events on.
    - returns: The throttled sequence.
    */
    public func debounce(_ dueTime: RxTimeInterval, scheduler: SchedulerType)
        -> Observable<E> {
        return Debounce(source: self.asObservable(), dueTime: dueTime, scheduler: scheduler)
    }
}

// MARK: sample

extension ObservableType {
   
    /**
    Samples the source observable sequence using a sampler observable sequence producing sampling ticks.
    
    Upon each sampling tick, the latest element (if any) in the source sequence during the last sampling interval is sent to the resulting sequence.
    
    **In case there were no new elements between sampler ticks, no element is sent to the resulting sequence.**

    - seealso: [sample operator on reactivex.io](http://reactivex.io/documentation/operators/sample.html)
    
    - parameter sampler: Sampling tick sequence.
    - returns: Sampled observable sequence.
    */
    public func sample<O: ObservableType>(_ sampler: O)
        -> Observable<E> {
        return Sample(source: self.asObservable(), sampler: sampler.asObservable())
    }
}

extension Observable where Element : SignedInteger {
    /**
    Returns an observable sequence that produces a value after each period, using the specified scheduler to run timers and to send out observer messages.

    - seealso: [interval operator on reactivex.io](http://reactivex.io/documentation/operators/interval.html)

    - parameter period: Period for producing the values in the resulting sequence.
    - parameter scheduler: Scheduler to run the timer on.
    - returns: An observable sequence that produces a value after each period.
    */
    public static func interval(_ period: RxTimeInterval, scheduler: SchedulerType)
        -> Observable<E> {
        return Timer(dueTime: period,
            period: period,
            scheduler: scheduler
        )
    }
}

// MARK: timer

extension Observable where Element: SignedInteger {
    /**
    Returns an observable sequence that periodically produces a value after the specified initial relative due time has elapsed, using the specified scheduler to run timers.

    - seealso: [timer operator on reactivex.io](http://reactivex.io/documentation/operators/timer.html)

    - parameter dueTime: Relative time at which to produce the first value.
    - parameter period: Period to produce subsequent values.
    - parameter scheduler: Scheduler to run timers on.
    - returns: An observable sequence that produces a value after due time has elapsed and then each period.
    */
    public static func timer(_ dueTime: RxTimeInterval, period: RxTimeInterval? = nil, scheduler: SchedulerType)
        -> Observable<E> {
        return Timer(
            dueTime: dueTime,
            period: period,
            scheduler: scheduler
        )
    }
}

// MARK: take

extension ObservableType {

    /**
    Takes elements for the specified duration from the start of the observable source sequence, using the specified scheduler to run timers.

    - seealso: [take operator on reactivex.io](http://reactivex.io/documentation/operators/take.html)
    
    - parameter duration: Duration for taking elements from the start of the sequence.
    - parameter scheduler: Scheduler to run the timer on.
    - returns: An observable sequence with the elements taken during the specified duration from the start of the source sequence.
    */
    public func take(_ duration: RxTimeInterval, scheduler: SchedulerType)
        -> Observable<E> {
        return TakeTime(source: self.asObservable(), duration: duration, scheduler: scheduler)
    }
}

// MARK: skip

extension ObservableType {
    
    /**
    Skips elements for the specified duration from the start of the observable source sequence, using the specified scheduler to run timers.

    - seealso: [skip operator on reactivex.io](http://reactivex.io/documentation/operators/skip.html)
    
    - parameter duration: Duration for skipping elements from the start of the sequence.
    - parameter scheduler: Scheduler to run the timer on.
    - returns: An observable sequence with the elements skipped during the specified duration from the start of the source sequence.
    */
    public func skip(_ duration: RxTimeInterval, scheduler: SchedulerType)
        -> Observable<E> {
        return SkipTime(source: self.asObservable(), duration: duration, scheduler: scheduler)
    }
}

// MARK: ignoreElements

extension ObservableType {

    /**
     Skips elements and completes (or errors) when the receiver completes (or errors). Equivalent to filter that always returns false.

     - seealso: [ignoreElements operator on reactivex.io](http://reactivex.io/documentation/operators/ignoreelements.html)

     - returns: An observable sequence that skips all elements of the source sequence.
     */
    public func ignoreElements()
        -> Observable<E> {
            return filter { _ -> Bool in
                return false
            }
    }
}

// MARK: delaySubscription

extension ObservableType {
    
    /**
    Time shifts the observable sequence by delaying the subscription with the specified relative time duration, using the specified scheduler to run timers.

    - seealso: [delay operator on reactivex.io](http://reactivex.io/documentation/operators/delay.html)
    
    - parameter dueTime: Relative time shift of the subscription.
    - parameter scheduler: Scheduler to run the subscription delay timer on.
    - returns: Time-shifted sequence.
    */
    public func delaySubscription(_ dueTime: RxTimeInterval, scheduler: SchedulerType)
        -> Observable<E> {
        return DelaySubscription(source: self.asObservable(), dueTime: dueTime, scheduler: scheduler)
    }
}

// MARK: buffer

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
    public func buffer(timeSpan: RxTimeInterval, count: Int, scheduler: SchedulerType)
        -> Observable<[E]> {
        return BufferTimeCount(source: self.asObservable(), timeSpan: timeSpan, count: count, scheduler: scheduler)
    }
}

// MARK: window

extension ObservableType {
    
    /**
     Projects each element of an observable sequence into a window that is completed when either it’s full or a given amount of time has elapsed.

     - seealso: [window operator on reactivex.io](http://reactivex.io/documentation/operators/window.html)
          
     - parameter timeSpan: Maximum time length of a window.
     - parameter count: Maximum element count of a window.
     - parameter scheduler: Scheduler to run windowing timers on.
     - returns: An observable sequence of windows (instances of `Observable`).
     */
    public func window(timeSpan: RxTimeInterval, count: Int, scheduler: SchedulerType)
        -> Observable<Observable<E>> {
            return WindowTimeCount(source: self.asObservable(), timeSpan: timeSpan, count: count, scheduler: scheduler)
    }
}

// MARK: timeout

extension ObservableType {
    
    /**
     Applies a timeout policy for each element in the observable sequence. If the next element isn't received within the specified timeout duration starting from its predecessor, a TimeoutError is propagated to the observer.

     - seealso: [timeout operator on reactivex.io](http://reactivex.io/documentation/operators/timeout.html)
     
     - parameter dueTime: Maximum duration between values before a timeout occurs.
     - parameter scheduler: Scheduler to run the timeout timer on.
     - returns: An observable sequence with a TimeoutError in case of a timeout.
     */
    public func timeout(_ dueTime: RxTimeInterval, scheduler: SchedulerType)
        -> Observable<E> {
            return Timeout(source: self.asObservable(), dueTime: dueTime, other: Observable.error(RxError.timeout), scheduler: scheduler)
    }

    /**
     Applies a timeout policy for each element in the observable sequence, using the specified scheduler to run timeout timers. If the next element isn't received within the specified timeout duration starting from its predecessor, the other observable sequence is used to produce future messages from that point on.

     - seealso: [timeout operator on reactivex.io](http://reactivex.io/documentation/operators/timeout.html)
     
     - parameter dueTime: Maximum duration between values before a timeout occurs.
     - parameter other: Sequence to return in case of a timeout.
     - parameter scheduler: Scheduler to run the timeout timer on.
     - returns: The source sequence switching to the other sequence in case of a timeout.
     */
    public func timeout<O: ObservableConvertibleType>(_ dueTime: RxTimeInterval, other: O, scheduler: SchedulerType)
        -> Observable<E> where E == O.E {
            return Timeout(source: self.asObservable(), dueTime: dueTime, other: other.asObservable(), scheduler: scheduler)
    }
}

// MARK: delay

extension ObservableType {
    
    /**
     Returns an observable sequence by the source observable sequence shifted forward in time by a specified delay. Error events from the source observable sequence are not delayed.
     
     - seealso: [delay operator on reactivex.io](http://reactivex.io/documentation/operators/delay.html)
     
     - parameter dueTime: Relative time shift of the source by.
     - parameter scheduler: Scheduler to run the subscription delay timer on.
     - returns: the source Observable shifted in time by the specified delay.
     */
    public func delay(_ dueTime: RxTimeInterval, scheduler: SchedulerType)
        -> Observable<E> {
            return Delay(source: self.asObservable(), dueTime: dueTime, scheduler: scheduler)
    }
}
