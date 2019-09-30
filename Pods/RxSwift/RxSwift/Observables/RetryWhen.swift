//
//  RetryWhen.swift
//  RxSwift
//
//  Created by Junior B. on 06/10/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {

    /**
     Repeats the source observable sequence on error when the notifier emits a next value.
     If the source observable errors and the notifier completes, it will complete the source sequence.

     - seealso: [retry operator on reactivex.io](http://reactivex.io/documentation/operators/retry.html)

     - parameter notificationHandler: A handler that is passed an observable sequence of errors raised by the source observable and returns and observable that either continues, completes or errors. This behavior is then applied to the source observable.
     - returns: An observable sequence producing the elements of the given sequence repeatedly until it terminates successfully or is notified to error or complete.
     */
    public func retryWhen<TriggerObservable: ObservableType, Error: Swift.Error>(_ notificationHandler: @escaping (Observable<Error>) -> TriggerObservable)
        -> Observable<E> {
        return RetryWhenSequence(sources: InfiniteSequence(repeatedValue: self.asObservable()), notificationHandler: notificationHandler)
    }

    /**
     Repeats the source observable sequence on error when the notifier emits a next value.
     If the source observable errors and the notifier completes, it will complete the source sequence.

     - seealso: [retry operator on reactivex.io](http://reactivex.io/documentation/operators/retry.html)

     - parameter notificationHandler: A handler that is passed an observable sequence of errors raised by the source observable and returns and observable that either continues, completes or errors. This behavior is then applied to the source observable.
     - returns: An observable sequence producing the elements of the given sequence repeatedly until it terminates successfully or is notified to error or complete.
     */
    public func retryWhen<TriggerObservable: ObservableType>(_ notificationHandler: @escaping (Observable<Swift.Error>) -> TriggerObservable)
        -> Observable<E> {
        return RetryWhenSequence(sources: InfiniteSequence(repeatedValue: self.asObservable()), notificationHandler: notificationHandler)
    }
}

final private class RetryTriggerSink<S: Sequence, O: ObserverType, TriggerObservable: ObservableType, Error>
    : ObserverType where S.Iterator.Element: ObservableType, S.Iterator.Element.E == O.E {
    typealias E = TriggerObservable.E
    
    typealias Parent = RetryWhenSequenceSinkIter<S, O, TriggerObservable, Error>
    
    fileprivate let _parent: Parent

    init(parent: Parent) {
        self._parent = parent
    }

    func on(_ event: Event<E>) {
        switch event {
        case .next:
            self._parent._parent._lastError = nil
            self._parent._parent.schedule(.moveNext)
        case .error(let e):
            self._parent._parent.forwardOn(.error(e))
            self._parent._parent.dispose()
        case .completed:
            self._parent._parent.forwardOn(.completed)
            self._parent._parent.dispose()
        }
    }
}

final private class RetryWhenSequenceSinkIter<S: Sequence, O: ObserverType, TriggerObservable: ObservableType, Error>
    : ObserverType
    , Disposable where S.Iterator.Element: ObservableType, S.Iterator.Element.E == O.E {
    typealias E = O.E
    typealias Parent = RetryWhenSequenceSink<S, O, TriggerObservable, Error>

    fileprivate let _parent: Parent
    fileprivate let _errorHandlerSubscription = SingleAssignmentDisposable()
    fileprivate let _subscription: Disposable

    init(parent: Parent, subscription: Disposable) {
        self._parent = parent
        self._subscription = subscription
    }

    func on(_ event: Event<E>) {
        switch event {
        case .next:
            self._parent.forwardOn(event)
        case .error(let error):
            self._parent._lastError = error

            if let failedWith = error as? Error {
                // dispose current subscription
                self._subscription.dispose()

                let errorHandlerSubscription = self._parent._notifier.subscribe(RetryTriggerSink(parent: self))
                self._errorHandlerSubscription.setDisposable(errorHandlerSubscription)
                self._parent._errorSubject.on(.next(failedWith))
            }
            else {
                self._parent.forwardOn(.error(error))
                self._parent.dispose()
            }
        case .completed:
            self._parent.forwardOn(event)
            self._parent.dispose()
        }
    }

    final func dispose() {
        self._subscription.dispose()
        self._errorHandlerSubscription.dispose()
    }
}

final private class RetryWhenSequenceSink<S: Sequence, O: ObserverType, TriggerObservable: ObservableType, Error>
    : TailRecursiveSink<S, O> where S.Iterator.Element: ObservableType, S.Iterator.Element.E == O.E {
    typealias Element = O.E
    typealias Parent = RetryWhenSequence<S, TriggerObservable, Error>
    
    let _lock = RecursiveLock()
    
    fileprivate let _parent: Parent
    
    fileprivate var _lastError: Swift.Error?
    fileprivate let _errorSubject = PublishSubject<Error>()
    fileprivate let _handler: Observable<TriggerObservable.E>
    fileprivate let _notifier = PublishSubject<TriggerObservable.E>()

    init(parent: Parent, observer: O, cancel: Cancelable) {
        self._parent = parent
        self._handler = parent._notificationHandler(self._errorSubject).asObservable()
        super.init(observer: observer, cancel: cancel)
    }
    
    override func done() {
        if let lastError = self._lastError {
            self.forwardOn(.error(lastError))
            self._lastError = nil
        }
        else {
            self.forwardOn(.completed)
        }

        self.dispose()
    }
    
    override func extract(_ observable: Observable<E>) -> SequenceGenerator? {
        // It is important to always return `nil` here because there are sideffects in the `run` method
        // that are dependant on particular `retryWhen` operator so single operator stack can't be reused in this
        // case.
        return nil
    }

    override func subscribeToNext(_ source: Observable<E>) -> Disposable {
        let subscription = SingleAssignmentDisposable()
        let iter = RetryWhenSequenceSinkIter(parent: self, subscription: subscription)
        subscription.setDisposable(source.subscribe(iter))
        return iter
    }

    override func run(_ sources: SequenceGenerator) -> Disposable {
        let triggerSubscription = self._handler.subscribe(self._notifier.asObserver())
        let superSubscription = super.run(sources)
        return Disposables.create(superSubscription, triggerSubscription)
    }
}

final private class RetryWhenSequence<S: Sequence, TriggerObservable: ObservableType, Error>: Producer<S.Iterator.Element.E> where S.Iterator.Element: ObservableType {
    typealias Element = S.Iterator.Element.E
    
    fileprivate let _sources: S
    fileprivate let _notificationHandler: (Observable<Error>) -> TriggerObservable
    
    init(sources: S, notificationHandler: @escaping (Observable<Error>) -> TriggerObservable) {
        self._sources = sources
        self._notificationHandler = notificationHandler
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        let sink = RetryWhenSequenceSink<S, O, TriggerObservable, Error>(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run((self._sources.makeIterator(), nil))
        return (sink: sink, subscription: subscription)
    }
}
