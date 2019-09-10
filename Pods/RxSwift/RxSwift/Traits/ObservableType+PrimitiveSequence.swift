//
//  ObservableType+PrimitiveSequence.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 9/17/17.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {
    /**
     The `asSingle` operator throws a `RxError.noElements` or `RxError.moreThanOneElement`
     if the source Observable does not emit exactly one element before successfully completing.

     - seealso: [single operator on reactivex.io](http://reactivex.io/documentation/operators/first.html)

     - returns: An observable sequence that emits a single element when the source Observable has completed, or throws an exception if more (or none) of them are emitted.
     */
    public func asSingle() -> Single<E> {
        return PrimitiveSequence(raw: AsSingle(source: self.asObservable()))
    }
    
    /**
     The `first` operator emits only the very first item emitted by this Observable,
     or nil if this Observable completes without emitting anything.
     
     - seealso: [single operator on reactivex.io](http://reactivex.io/documentation/operators/first.html)
     
     - returns: An observable sequence that emits a single element or nil if the source observable sequence completes without emitting any items.
     */
    public func first() -> Single<E?> {
        return PrimitiveSequence(raw: First(source: self.asObservable()))
    }

    /**
     The `asMaybe` operator throws a `RxError.moreThanOneElement`
     if the source Observable does not emit at most one element before successfully completing.

     - seealso: [single operator on reactivex.io](http://reactivex.io/documentation/operators/first.html)

     - returns: An observable sequence that emits a single element, completes when the source Observable has completed, or throws an exception if more of them are emitted.
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
