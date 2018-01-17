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

final fileprivate class RetryTriggerSink<S: Sequence, O: ObserverType, TriggerObservable: ObservableType, Error>
    : ObserverType where S.Iterator.Element : ObservableType, S.Iterator.Element.E == O.E {
    typealias E = TriggerObservable.E
    
    typealias Parent = RetryWhenSequenceSinkIter<S, O, TriggerObservable, Error>
    
    fileprivate let _parent: Parent

    init(parent: Parent) {
        _parent = parent
    }

    func on(_ event: Event<E>) {
        switch event {
        case .next:
            _parent._parent._lastError = nil
            _parent._parent.schedule(.moveNext)
        case .error(let e):
            _parent._parent.forwardOn(.error(e))
            _parent._parent.dispose()
        case .completed:
            _parent._parent.forwardOn(.completed)
            _parent._parent.dispose()
        }
    }
}

final fileprivate class RetryWhenSequenceSinkIter<S: Sequence, O: ObserverType, TriggerObservable: ObservableType, Error>
    : ObserverType
    , Disposable where S.Iterator.Element : ObservableType, S.Iterator.Element.E == O.E {
    typealias E = O.E
    typealias Parent = RetryWhenSequenceSink<S, O, TriggerObservable, Error>

    fileprivate let _parent: Parent
    fileprivate let _errorHandlerSubscription = SingleAssignmentDisposable()
    fileprivate let _subscription: Disposable

    init(parent: Parent, subscription: Disposable) {
        _parent = parent
        _subscription = subscription
    }

    func on(_ event: Event<E>) {
        switch event {
        case .next:
            _parent.forwardOn(event)
        case .error(let error):
            _parent._lastError = error

            if let failedWith = error as? Error {
                // dispose current subscription
                _subscription.dispose()

                let errorHandlerSubscription = _parent._notifier.subscribe(RetryTriggerSink(parent: self))
                _errorHandlerSubscription.setDisposable(errorHandlerSubscription)
                _parent._errorSubject.on(.next(failedWith))
            }
            else {
                _parent.forwardOn(.error(error))
                _parent.dispose()
            }
        case .completed:
            _parent.forwardOn(event)
            _parent.dispose()
        }
    }

    final func dispose() {
        _subscription.dispose()
        _errorHandlerSubscription.dispose()
    }
}

final fileprivate class RetryWhenSequenceSink<S: Sequence, O: ObserverType, TriggerObservable: ObservableType, Error>
    : TailRecursiveSink<S, O> where S.Iterator.Element : ObservableType, S.Iterator.Element.E == O.E {
    typealias Element = O.E
    typealias Parent = RetryWhenSequence<S, TriggerObservable, Error>
    
    let _lock = RecursiveLock()
    
    fileprivate let _parent: Parent
    
    fileprivate var _lastError: Swift.Error?
    fileprivate let _errorSubject = PublishSubject<Error>()
    fileprivate let _handler: Observable<TriggerObservable.E>
    fileprivate let _notifier = PublishSubject<TriggerObservable.E>()

    init(parent: Parent, observer: O, cancel: Cancelable) {
        _parent = parent
        _handler = parent._notificationHandler(_errorSubject).asObservable()
        super.init(observer: observer, cancel: cancel)
    }
    
    override func done() {
        if let lastError = _lastError {
            forwardOn(.error(lastError))
            _lastError = nil
        }
        else {
            forwardOn(.completed)
        }

        dispose()
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
        let triggerSubscription = _handler.subscribe(_notifier.asObserver())
        let superSubscription = super.run(sources)
        return Disposables.create(superSubscription, triggerSubscription)
    }
}

final fileprivate class RetryWhenSequence<S: Sequence, TriggerObservable: ObservableType, Error> : Producer<S.Iterator.Element.E> where S.Iterator.Element : ObservableType {
    typealias Element = S.Iterator.Element.E
    
    fileprivate let _sources: S
    fileprivate let _notificationHandler: (Observable<Error>) -> TriggerObservable
    
    init(sources: S, notificationHandler: @escaping (Observable<Error>) -> TriggerObservable) {
        _sources = sources
        _notificationHandler = notificationHandler
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        let sink = RetryWhenSequenceSink<S, O, TriggerObservable, Error>(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run((self._sources.makeIterator(), nil))
        return (sink: sink, subscription: subscription)
    }
}
