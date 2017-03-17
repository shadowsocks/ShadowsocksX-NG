//
//  RetryWhen.swift
//  RxSwift
//
//  Created by Junior B. on 06/10/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

class RetryTriggerSink<S: Sequence, O: ObserverType, TriggerObservable: ObservableType, Error>
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

class RetryWhenSequenceSinkIter<S: Sequence, O: ObserverType, TriggerObservable: ObservableType, Error>
    : SingleAssignmentDisposable
    , ObserverType where S.Iterator.Element : ObservableType, S.Iterator.Element.E == O.E {
    typealias E = O.E
    typealias Parent = RetryWhenSequenceSink<S, O, TriggerObservable, Error>

    fileprivate let _parent: Parent
    fileprivate let _errorHandlerSubscription = SingleAssignmentDisposable()

    init(parent: Parent) {
        _parent = parent
    }

    func on(_ event: Event<E>) {
        switch event {
        case .next:
            _parent.forwardOn(event)
        case .error(let error):
            _parent._lastError = error

            if let failedWith = error as? Error {
                // dispose current subscription
                super.dispose()

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

    override func dispose() {
        super.dispose()
        _errorHandlerSubscription.dispose()
    }
}

class RetryWhenSequenceSink<S: Sequence, O: ObserverType, TriggerObservable: ObservableType, Error>
    : TailRecursiveSink<S, O> where S.Iterator.Element : ObservableType, S.Iterator.Element.E == O.E {
    typealias Element = O.E
    typealias Parent = RetryWhenSequence<S, TriggerObservable, Error>
    
    let _lock = NSRecursiveLock()
    
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
        let iter = RetryWhenSequenceSinkIter(parent: self)
        iter.setDisposable(source.subscribe(iter))
        return iter
    }

    override func run(_ sources: SequenceGenerator) -> Disposable {
        let triggerSubscription = _handler.subscribe(_notifier.asObserver())
        let superSubscription = super.run(sources)
        return Disposables.create(superSubscription, triggerSubscription)
    }
}

class RetryWhenSequence<S: Sequence, TriggerObservable: ObservableType, Error> : Producer<S.Iterator.Element.E> where S.Iterator.Element : ObservableType {
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
