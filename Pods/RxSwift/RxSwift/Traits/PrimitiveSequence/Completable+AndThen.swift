//
//  Completable+AndThen.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 7/2/17.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

extension PrimitiveSequenceType where Trait == CompletableTrait, Element == Never {
    /**
     Concatenates the second observable sequence to `self` upon successful termination of `self`.

     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)

     - parameter second: Second observable sequence.
     - returns: An observable sequence that contains the elements of `self`, followed by those of the second sequence.
     */
    public func andThen<Element>(_ second: Single<Element>) -> Single<Element> {
        let completable = self.primitiveSequence.asObservable()
        return Single(raw: ConcatCompletable(completable: completable, second: second.asObservable()))
    }

    /**
     Concatenates the second observable sequence to `self` upon successful termination of `self`.

     - seealso: [concat operator on reactivex.io](http://reactivex.io/documentation/operators/concat.html)

     - parameter second: Second observable sequence.
     - returns: An observable sequence that contains the elements of `self`, followed by those of the second sequence.
     */
    public func andThen<Element>(_ second: Maybe<Element>) -> Maybe<Element> {
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
    public func andThen<Element>(_ second: Observable<Element>) -> Observable<Element> {
        let completable = self.primitiveSequence.asObservable()
        return ConcatCompletable(completable: completable, second: second.asObservable())
    }
}

final private class ConcatCompletable<Element>: Producer<Element> {
    fileprivate let completable: Observable<Never>
    fileprivate let second: Observable<Element>

    init(completable: Observable<Never>, second: Observable<Element>) {
        self.completable = completable
        self.second = second
    }

    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == Element {
        let sink = ConcatCompletableSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}

final private class ConcatCompletableSink<Observer: ObserverType>
    : Sink<Observer>
    , ObserverType {
    typealias Element = Never
    typealias Parent = ConcatCompletable<Observer.Element>

    private let parent: Parent
    private let subscription = SerialDisposable()
    
    init(parent: Parent, observer: Observer, cancel: Cancelable) {
        self.parent = parent
        super.init(observer: observer, cancel: cancel)
    }

    func on(_ event: Event<Element>) {
        switch event {
        case .error(let error):
            self.forwardOn(.error(error))
            self.dispose()
        case .next:
            break
        case .completed:
            let otherSink = ConcatCompletableSinkOther(parent: self)
            self.subscription.disposable = self.parent.second.subscribe(otherSink)
        }
    }

    func run() -> Disposable {
        let subscription = SingleAssignmentDisposable()
        self.subscription.disposable = subscription
        subscription.setDisposable(self.parent.completable.subscribe(self))
        return self.subscription
    }
}

final private class ConcatCompletableSinkOther<Observer: ObserverType>
    : ObserverType {
    typealias Element = Observer.Element 

    typealias Parent = ConcatCompletableSink<Observer>
    
    private let parent: Parent

    init(parent: Parent) {
        self.parent = parent
    }

    func on(_ event: Event<Observer.Element>) {
        self.parent.forwardOn(event)
        if event.isStopEvent {
            self.parent.dispose()
        }
    }
}
