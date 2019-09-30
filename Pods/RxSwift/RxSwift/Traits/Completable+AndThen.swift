//
//  Completable+AndThen.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 7/2/17.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

extension PrimitiveSequenceType where TraitType == CompletableTrait, ElementType == Never {
    /**
     Concatenates the second observable sequence to `self` upon successful termination of `self`.

     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)

     - parameter second: Second observable sequence.
     - returns: An observable sequence that contains the elements of `self`, followed by those of the second sequence.
     */
    public func andThen<E>(_ second: Single<E>) -> Single<E> {
        let completable = self.primitiveSequence.asObservable()
        return Single(raw: ConcatCompletable(completable: completable, second: second.asObservable()))
    }

    /**
     Concatenates the second observable sequence to `self` upon successful termination of `self`.

     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)

     - parameter second: Second observable sequence.
     - returns: An observable sequence that contains the elements of `self`, followed by those of the second sequence.
     */
    public func andThen<E>(_ second: Maybe<E>) -> Maybe<E> {
        let completable = self.primitiveSequence.asObservable()
        return Maybe(raw: ConcatCompletable(completable: completable, second: second.asObservable()))
    }

    /**
     Concatenates the second observable sequence to `self` upon successful termination of `self`.

     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)

     - parameter second: Second observable sequence.
     - returns: An observable sequence that contains the elements of `self`, followed by those of the second sequence.
     */
    public func andThen(_ second: Completable) -> Completable {
        let completable = self.primitiveSequence.asObservable()
        return Completable(raw: ConcatCompletable(completable: completable, second: second.asObservable()))
    }

    /**
     Concatenates the second observable sequence to `self` upon successful termination of `self`.

     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)

     - parameter second: Second observable sequence.
     - returns: An observable sequence that contains the elements of `self`, followed by those of the second sequence.
     */
    public func andThen<E>(_ second: Observable<E>) -> Observable<E> {
        let completable = self.primitiveSequence.asObservable()
        return ConcatCompletable(completable: completable, second: second.asObservable())
    }
}

final private class ConcatCompletable<Element>: Producer<Element> {
    fileprivate let _completable: Observable<Never>
    fileprivate let _second: Observable<Element>

    init(completable: Observable<Never>, second: Observable<Element>) {
        self._completable = completable
        self._second = second
    }

    override func run<O>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O : ObserverType, O.E == Element {
        let sink = ConcatCompletableSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}

final private class ConcatCompletableSink<O: ObserverType>
    : Sink<O>
    , ObserverType {
    typealias E = Never
    typealias Parent = ConcatCompletable<O.E>

    private let _parent: Parent
    private let _subscription = SerialDisposable()
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        self._parent = parent
        super.init(observer: observer, cancel: cancel)
    }

    func on(_ event: Event<E>) {
        switch event {
        case .error(let error):
            self.forwardOn(.error(error))
            self.dispose()
        case .next:
            break
        case .completed:
            let otherSink = ConcatCompletableSinkOther(parent: self)
            self._subscription.disposable = self._parent._second.subscribe(otherSink)
        }
    }

    func run() -> Disposable {
        let subscription = SingleAssignmentDisposable()
        self._subscription.disposable = subscription
        subscription.setDisposable(self._parent._completable.subscribe(self))
        return self._subscription
    }
}

final private class ConcatCompletableSinkOther<O: ObserverType>
    : ObserverType {
    typealias E = O.E

    typealias Parent = ConcatCompletableSink<O>
    
    private let _parent: Parent

    init(parent: Parent) {
        self._parent = parent
    }

    func on(_ event: Event<O.E>) {
        self._parent.forwardOn(event)
        if event.isStopEvent {
            self._parent.dispose()
        }
    }
}
