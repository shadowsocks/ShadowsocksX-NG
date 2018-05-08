//
//  Concat.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/21/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

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

extension ObservableType {
    /**
     Concatenates all observable sequences in the given sequence, as long as the previous observable sequence terminated successfully.

     This operator has tail recursive optimizations that will prevent stack overflow.

     Optimizations will be performed in cases equivalent to following:

     [1, [2, [3, .....].concat()].concat].concat()

     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)

     - returns: An observable sequence that contains the elements of each given sequence, in sequential order.
     */
    public static func concat<S: Sequence >(_ sequence: S) -> Observable<E>
        where S.Iterator.Element == Observable<E> {
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
    public static func concat<S: Collection >(_ collection: S) -> Observable<E>
        where S.Iterator.Element == Observable<E> {
            return Concat(sources: collection, count: Int64(collection.count))
    }

    /**
     Concatenates all observable sequences in the given collection, as long as the previous observable sequence terminated successfully.

     This operator has tail recursive optimizations that will prevent stack overflow.

     Optimizations will be performed in cases equivalent to following:

     [1, [2, [3, .....].concat()].concat].concat()

     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)

     - returns: An observable sequence that contains the elements of each given sequence, in sequential order.
     */
    public static func concat(_ sources: Observable<E> ...) -> Observable<E> {
        return Concat(sources: sources, count: Int64(sources.count))
    }
}

final fileprivate class ConcatSink<S: Sequence, O: ObserverType>
    : TailRecursiveSink<S, O>
    , ObserverType where S.Iterator.Element : ObservableConvertibleType, S.Iterator.Element.E == O.E {
    typealias Element = O.E
    
    override init(observer: O, cancel: Cancelable) {
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<Element>){
        switch event {
        case .next:
            forwardOn(event)
        case .error:
            forwardOn(event)
            dispose()
        case .completed:
            schedule(.moveNext)
        }
    }

    override func subscribeToNext(_ source: Observable<E>) -> Disposable {
        return source.subscribe(self)
    }
    
    override func extract(_ observable: Observable<E>) -> SequenceGenerator? {
        if let source = observable as? Concat<S> {
            return (source._sources.makeIterator(), source._count)
        }
        else {
            return nil
        }
    }
}

final fileprivate class Concat<S: Sequence> : Producer<S.Iterator.Element.E> where S.Iterator.Element : ObservableConvertibleType {
    typealias Element = S.Iterator.Element.E
    
    fileprivate let _sources: S
    fileprivate let _count: IntMax?

    init(sources: S, count: IntMax?) {
        _sources = sources
        _count = count
    }
    
    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        let sink = ConcatSink<S, O>(observer: observer, cancel: cancel)
        let subscription = sink.run((_sources.makeIterator(), _count))
        return (sink: sink, subscription: subscription)
    }
}

