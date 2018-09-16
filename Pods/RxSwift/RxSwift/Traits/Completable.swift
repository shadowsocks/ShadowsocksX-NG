//
//  Completable.swift
//  RxSwift
//
//  Created by sergdort on 19/08/2017.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

#if DEBUG
import Foundation
#endif

/// Sequence containing 0 elements
public enum CompletableTrait { }
/// Represents a push style sequence containing 0 elements.
public typealias Completable = PrimitiveSequence<CompletableTrait, Swift.Never>

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
        #if DEBUG
                let callStack = Hooks.recordCallStackOnError ? Thread.callStackSymbols : []
        #else
                let callStack = [String]()
        #endif

        return self.primitiveSequence.subscribe { event in
            switch event {
            case .error(let error):
                if let onError = onError {
                    onError(error)
                } else {
                    Hooks.defaultErrorHandler(callStack, error)
                }
            case .completed:
                onCompleted?()
            }
        }
    }
}

public extension PrimitiveSequenceType where TraitType == CompletableTrait, ElementType == Swift.Never {
    /**
     Returns an observable sequence that terminates with an `error`.

     - seealso: [throw operator on reactivex.io](http://reactivex.io/documentation/operators/empty-never-throw.html)

     - returns: The observable sequence that terminates with specified error.
     */
    public static func error(_ error: Swift.Error) -> Completable {
        return PrimitiveSequence(raw: Observable.error(error))
    }

    /**
     Returns a non-terminating observable sequence, which can be used to denote an infinite duration.

     - seealso: [never operator on reactivex.io](http://reactivex.io/documentation/operators/empty-never-throw.html)

     - returns: An observable sequence whose observers will never get called.
     */
    public static func never() -> Completable {
        return PrimitiveSequence(raw: Observable.never())
    }

    /**
     Returns an empty observable sequence, using the specified scheduler to send out the single `Completed` message.

     - seealso: [empty operator on reactivex.io](http://reactivex.io/documentation/operators/empty-never-throw.html)

     - returns: An observable sequence with no elements.
     */
    public static func empty() -> Completable {
        return Completable(raw: Observable.empty())
    }

}

public extension PrimitiveSequenceType where TraitType == CompletableTrait, ElementType == Swift.Never {    
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
    public func `do`(onError: ((Swift.Error) throws -> Void)? = nil,
                     onCompleted: (() throws -> Void)? = nil,
                     onSubscribe: (() -> ())? = nil,
                     onSubscribed: (() -> ())? = nil,
                     onDispose: (() -> ())? = nil)
        -> Completable {
            return Completable(raw: primitiveSequence.source.do(
                onError: onError,
                onCompleted: onCompleted,
                onSubscribe: onSubscribe,
                onSubscribed: onSubscribed,
                onDispose: onDispose)
            )
    }



    /**
     Concatenates the second observable sequence to `self` upon successful termination of `self`.
     
     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)
     
     - parameter second: Second observable sequence.
     - returns: An observable sequence that contains the elements of `self`, followed by those of the second sequence.
     */
    public func concat(_ second: Completable) -> Completable {
        return Completable.concat(primitiveSequence, second)
    }
    
    /**
     Concatenates all observable sequences in the given sequence, as long as the previous observable sequence terminated successfully.
     
     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)
     
     - returns: An observable sequence that contains the elements of each given sequence, in sequential order.
     */
    public static func concat<S: Sequence>(_ sequence: S) -> Completable
        where S.Iterator.Element == Completable {
            let source = Observable.concat(sequence.lazy.map { $0.asObservable() })
            return Completable(raw: source)
    }
    
    /**
     Concatenates all observable sequences in the given sequence, as long as the previous observable sequence terminated successfully.
     
     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)
     
     - returns: An observable sequence that contains the elements of each given sequence, in sequential order.
     */
    public static func concat<C: Collection>(_ collection: C) -> Completable
        where C.Iterator.Element == Completable {
            let source = Observable.concat(collection.map { $0.asObservable() })
            return Completable(raw: source)
    }
    
    /**
     Concatenates all observable sequences in the given sequence, as long as the previous observable sequence terminated successfully.
     
     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)
     
     - returns: An observable sequence that contains the elements of each given sequence, in sequential order.
     */
    public static func concat(_ sources: Completable ...) -> Completable {
        let source = Observable.concat(sources.map { $0.asObservable() })
        return Completable(raw: source)
    }
    
    /**
     Merges elements from all observable sequences from collection into a single observable sequence.
     
     - seealso: [merge operator on reactivex.io](http://reactivex.io/documentation/operators/merge.html)
     
     - parameter sources: Collection of observable sequences to merge.
     - returns: The observable sequence that merges the elements of the observable sequences.
     */
    public static func merge<C: Collection>(_ sources: C) -> Completable
        where C.Iterator.Element == Completable {
            let source = Observable.merge(sources.map { $0.asObservable() })
            return Completable(raw: source)
    }
    
    /**
     Merges elements from all observable sequences from array into a single observable sequence.
     
     - seealso: [merge operator on reactivex.io](http://reactivex.io/documentation/operators/merge.html)
     
     - parameter sources: Array of observable sequences to merge.
     - returns: The observable sequence that merges the elements of the observable sequences.
     */
    public static func merge(_ sources: [Completable]) -> Completable {
        let source = Observable.merge(sources.map { $0.asObservable() })
        return Completable(raw: source)
    }
    
    /**
     Merges elements from all observable sequences into a single observable sequence.
     
     - seealso: [merge operator on reactivex.io](http://reactivex.io/documentation/operators/merge.html)
     
     - parameter sources: Collection of observable sequences to merge.
     - returns: The observable sequence that merges the elements of the observable sequences.
     */
    public static func merge(_ sources: Completable...) -> Completable {
        let source = Observable.merge(sources.map { $0.asObservable() })
        return Completable(raw: source)
    }
}
