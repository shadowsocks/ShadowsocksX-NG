//
//  Observable+Multiple.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/12/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

// MARK: combineLatest

extension Observable {
    /**
     Merges the specified observable sequences into one observable sequence by using the selector function whenever any of the observable sequences produces an element.

     - seealso: [combinelatest operator on reactivex.io](http://reactivex.io/documentation/operators/combinelatest.html)

     - parameter resultSelector: Function to invoke whenever any of the sources produces an element.
     - returns: An observable sequence containing the result of combining elements of the sources using the specified result selector function.
     */
    public static func combineLatest<C: Collection>(_ collection: C, _ resultSelector: @escaping ([C.Iterator.Element.E]) throws -> Element) -> Observable<Element>
        where C.Iterator.Element: ObservableType {
        return CombineLatestCollectionType(sources: collection, resultSelector: resultSelector)
    }
}

// MARK: zip

extension Observable {
    /**
     Merges the specified observable sequences into one observable sequence by using the selector function whenever all of the observable sequences have produced an element at a corresponding index.

     - seealso: [zip operator on reactivex.io](http://reactivex.io/documentation/operators/zip.html)

     - parameter resultSelector: Function to invoke for each series of elements at corresponding indexes in the sources.
     - returns: An observable sequence containing the result of combining elements of the sources using the specified result selector function.
     */
    public static func zip<C: Collection>(_ collection: C, _ resultSelector: @escaping ([C.Iterator.Element.E]) throws -> Element) -> Observable<Element>
    where C.Iterator.Element: ObservableType {
        return ZipCollectionType(sources: collection, resultSelector: resultSelector)
    }
}

// MARK: switch

extension ObservableType where E : ObservableConvertibleType {
    
    /**
    Transforms an observable sequence of observable sequences into an observable sequence
    producing values only from the most recent observable sequence.
    
    Each time a new inner observable sequence is received, unsubscribe from the
    previous inner observable sequence.

    - seealso: [switch operator on reactivex.io](http://reactivex.io/documentation/operators/switch.html)

    - returns: The observable sequence that at any point in time produces the elements of the most recent inner observable sequence that has been received.
    */
    public func switchLatest() -> Observable<E.E> {
        return Switch(source: asObservable())
    }
}

// MARK: concat

extension ObservableType {

    /**
    Concatenates the second observable sequence to `self` upon successful termination of `self`.

    - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)
    
    - parameter second: Second observable sequence.
    - returns: An observable sequence that contains the elements of `self`, followed by those of the second sequence.
    */
    public func concat<O: ObservableConvertibleType>(_ second: O) -> Observable<E> where O.E == E {
        return Observable.concat([self.asObservable(), second.asObservable()])
    }
}

extension Observable {
    /**
     Concatenates all observable sequences in the given sequence, as long as the previous observable sequence terminated successfully.

     This operator has tail recursive optimizations that will prevent stack overflow.

     Optimizations will be performed in cases equivalent to following:

     [1, [2, [3, .....].concat()].concat].concat()

     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)

     - returns: An observable sequence that contains the elements of each given sequence, in sequential order.
     */
    public static func concat<S: Sequence >(_ sequence: S) -> Observable<Element>
        where S.Iterator.Element == Observable<Element> {
            return Concat(sources: sequence, count: nil)
    }

    /**
     Concatenates all observable sequences in the given collection, as long as the previous observable sequence terminated successfully.

     This operator has tail recursive optimizations that will prevent stack overflow.

     Optimizations will be performed in cases equivalent to following:

     [1, [2, [3, .....].concat()].concat].concat()

     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)

     - returns: An observable sequence that contains the elements of each given sequence, in sequential order.
     */
    public static func concat<S: Collection >(_ collection: S) -> Observable<Element>
        where S.Iterator.Element == Observable<Element> {
            return Concat(sources: collection, count: collection.count.toIntMax())
    }
}

extension ObservableType where E : ObservableConvertibleType {
    
    /**
    Concatenates all inner observable sequences, as long as the previous observable sequence terminated successfully.

    - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)
    
    - returns: An observable sequence that contains the elements of each observed inner sequence, in sequential order.
    */
    public func concat() -> Observable<E.E> {
        return merge(maxConcurrent: 1)
    }
}

// MARK: merge

extension ObservableType where E : ObservableConvertibleType {
    
    /**
    Merges elements from all observable sequences in the given enumerable sequence into a single observable sequence.

    - seealso: [merge operator on reactivex.io](http://reactivex.io/documentation/operators/merge.html)
    
    - returns: The observable sequence that merges the elements of the observable sequences.
    */
    public func merge() -> Observable<E.E> {
        return Merge(source: asObservable())
    }

    /**
    Merges elements from all inner observable sequences into a single observable sequence, limiting the number of concurrent subscriptions to inner sequences.

    - seealso: [merge operator on reactivex.io](http://reactivex.io/documentation/operators/merge.html)

    - parameter maxConcurrent: Maximum number of inner observable sequences being subscribed to concurrently.
    - returns: The observable sequence that merges the elements of the inner sequences.
    */
    public func merge(maxConcurrent: Int)
        -> Observable<E.E> {
        return MergeLimited(source: asObservable(), maxConcurrent: maxConcurrent)
    }
}

// MARK: catch

extension ObservableType {
    
    /**
    Continues an observable sequence that is terminated by an error with the observable sequence produced by the handler.

    - seealso: [catch operator on reactivex.io](http://reactivex.io/documentation/operators/catch.html)
    
    - parameter handler: Error handler function, producing another observable sequence.
    - returns: An observable sequence containing the source sequence's elements, followed by the elements produced by the handler's resulting observable sequence in case an error occurred.
    */
    public func catchError(_ handler: @escaping (Swift.Error) throws -> Observable<E>)
        -> Observable<E> {
        return Catch(source: asObservable(), handler: handler)
    }

    /**
    Continues an observable sequence that is terminated by an error with a single element.

    - seealso: [catch operator on reactivex.io](http://reactivex.io/documentation/operators/catch.html)
    
    - parameter element: Last element in an observable sequence in case error occurs.
    - returns: An observable sequence containing the source sequence's elements, followed by the `element` in case an error occurred.
    */
    public func catchErrorJustReturn(_ element: E)
        -> Observable<E> {
        return Catch(source: asObservable(), handler: { _ in Observable.just(element) })
    }
    
}

extension Observable {
    /**
     Continues an observable sequence that is terminated by an error with the next observable sequence.

     - seealso: [catch operator on reactivex.io](http://reactivex.io/documentation/operators/catch.html)

     - returns: An observable sequence containing elements from consecutive source sequences until a source sequence terminates successfully.
     */
    public static func catchError<S: Sequence>(_ sequence: S) -> Observable<Element>
        where S.Iterator.Element == Observable<Element> {
        return CatchSequence(sources: sequence)
    }
}

// MARK: takeUntil

extension ObservableType {
    
    /**
    Returns the elements from the source observable sequence until the other observable sequence produces an element.

    - seealso: [takeUntil operator on reactivex.io](http://reactivex.io/documentation/operators/takeuntil.html)
    
    - parameter other: Observable sequence that terminates propagation of elements of the source sequence.
    - returns: An observable sequence containing the elements of the source sequence up to the point the other sequence interrupted further propagation.
    */
    public func takeUntil<O: ObservableType>(_ other: O)
        -> Observable<E> {
        return TakeUntil(source: asObservable(), other: other.asObservable())
    }
}

// MARK: skipUntil

extension ObservableType {
    
    /**
    Returns the elements from the source observable sequence that are emitted after the other observable sequence produces an element.

    - seealso: [skipUntil operator on reactivex.io](http://reactivex.io/documentation/operators/skipuntil.html)
    
    - parameter other: Observable sequence that starts propagation of elements of the source sequence.
    - returns: An observable sequence containing the elements of the source sequence that are emitted after the other sequence emits an item.
    */
    public func skipUntil<O: ObservableType>(_ other: O)
        -> Observable<E> {
        return SkipUntil(source: asObservable(), other: other.asObservable())
    }
}

// MARK: amb

extension ObservableType {
    
    /**
    Propagates the observable sequence that reacts first.

    - seealso: [amb operator on reactivex.io](http://reactivex.io/documentation/operators/amb.html)
    
    - parameter right: Second observable sequence.
    - returns: An observable sequence that surfaces either of the given sequences, whichever reacted first.
    */
    public func amb<O2: ObservableType>
        (_ right: O2)
        -> Observable<E> where O2.E == E {
        return Amb(left: asObservable(), right: right.asObservable())
    }
}

extension Observable {
    /**
     Propagates the observable sequence that reacts first.

     - seealso: [amb operator on reactivex.io](http://reactivex.io/documentation/operators/amb.html)

     - returns: An observable sequence that surfaces any of the given sequences, whichever reacted first.
     */
    public static func amb<S: Sequence>(_ sequence: S) -> Observable<Element>
        where S.Iterator.Element == Observable<Element> {
        return sequence.reduce(Observable<S.Iterator.Element.E>.never()) { a, o in
            return a.amb(o.asObservable())
        }
    }
}

// withLatestFrom

extension ObservableType {
    
    /**
    Merges two observable sequences into one observable sequence by combining each element from self with the latest element from the second source, if any.

    - seealso: [combineLatest operator on reactivex.io](http://reactivex.io/documentation/operators/combinelatest.html)
     
    - parameter second: Second observable source.
    - parameter resultSelector: Function to invoke for each element from the self combined with the latest element from the second source, if any.
    - returns: An observable sequence containing the result of combining each element of the self  with the latest element from the second source, if any, using the specified result selector function.
    */
    public func withLatestFrom<SecondO: ObservableConvertibleType, ResultType>(_ second: SecondO, resultSelector: @escaping (E, SecondO.E) throws -> ResultType) -> Observable<ResultType> {
        return WithLatestFrom(first: asObservable(), second: second.asObservable(), resultSelector: resultSelector)
    }

    /**
    Merges two observable sequences into one observable sequence by using latest element from the second sequence every time when `self` emitts an element.

    - seealso: [combineLatest operator on reactivex.io](http://reactivex.io/documentation/operators/combinelatest.html)
     
    - parameter second: Second observable source.
    - returns: An observable sequence containing the result of combining each element of the self  with the latest element from the second source, if any, using the specified result selector function.
    */
    public func withLatestFrom<SecondO: ObservableConvertibleType>(_ second: SecondO) -> Observable<SecondO.E> {
        return WithLatestFrom(first: asObservable(), second: second.asObservable(), resultSelector: { $1 })
    }
}
