//
//  WithLatestFrom.swift
//  RxSwift
//
//  Created by Yury Korolev on 10/19/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {

    /**
     Merges two observable sequences into one observable sequence by combining each element from self with the latest element from the second source, if any.

     - seealso: [combineLatest operator on reactivex.io](http://reactivex.io/documentation/operators/combinelatest.html)

     - parameter second: Second observable source.
     - parameter resultSelector: Function to invoke for each element from the self combined with the latest element from the second source, if any.
     - returns: An observable sequence containing the result of combining each element of the self  with the latest element from the second source, if any, using the specified result selector function.
     */
    public func withLatestFrom<SecondO: ObservableConvertibleType, ResultType>(_ second: SecondO, resultSelector: @escaping (E, SecondO.E) throws -> ResultType) -> Observable<ResultType> {
        return WithLatestFrom(first: self.asObservable(), second: second.asObservable(), resultSelector: resultSelector)
    }

    /**
     Merges two observable sequences into one observable sequence by using latest element from the second sequence every time when `self` emits an element.

     - seealso: [combineLatest operator on reactivex.io](http://reactivex.io/documentation/operators/combinelatest.html)

     - parameter second: Second observable source.
     - returns: An observable sequence containing the result of combining each element of the self  with the latest element from the second source, if any, using the specified result selector function.
     */
    public func withLatestFrom<SecondO: ObservableConvertibleType>(_ second: SecondO) -> Observable<SecondO.E> {
        return WithLatestFrom(first: self.asObservable(), second: second.asObservable(), resultSelector: { $1 })
    }
}

final private class WithLatestFromSink<FirstType, SecondType, O: ObserverType>
    : Sink<O>
    , ObserverType
    , LockOwnerType
    , SynchronizedOnType {
    typealias ResultType = O.E
    typealias Parent = WithLatestFrom<FirstType, SecondType, ResultType>
    typealias E = FirstType
    
    fileprivate let _parent: Parent
    
    var _lock = RecursiveLock()
    fileprivate var _latest: SecondType?

    init(parent: Parent, observer: O, cancel: Cancelable) {
        self._parent = parent
        
        super.init(observer: observer, cancel: cancel)
    }
    
    func run() -> Disposable {
        let sndSubscription = SingleAssignmentDisposable()
        let sndO = WithLatestFromSecond(parent: self, disposable: sndSubscription)
        
        sndSubscription.setDisposable(self._parent._second.subscribe(sndO))
        let fstSubscription = self._parent._first.subscribe(self)

        return Disposables.create(fstSubscription, sndSubscription)
    }

    func on(_ event: Event<E>) {
        self.synchronizedOn(event)
    }

    func _synchronized_on(_ event: Event<E>) {
        switch event {
        case let .next(value):
            guard let latest = self._latest else { return }
            do {
                let res = try self._parent._resultSelector(value, latest)
                
                self.forwardOn(.next(res))
            } catch let e {
                self.forwardOn(.error(e))
                self.dispose()
            }
        case .completed:
            self.forwardOn(.completed)
            self.dispose()
        case let .error(error):
            self.forwardOn(.error(error))
            self.dispose()
        }
    }
}

final private class WithLatestFromSecond<FirstType, SecondType, O: ObserverType>
    : ObserverType
    , LockOwnerType
    , SynchronizedOnType {
    
    typealias ResultType = O.E
    typealias Parent = WithLatestFromSink<FirstType, SecondType, O>
    typealias E = SecondType
    
    private let _parent: Parent
    private let _disposable: Disposable

    var _lock: RecursiveLock {
        return self._parent._lock
    }

    init(parent: Parent, disposable: Disposable) {
        self._parent = parent
        self._disposable = disposable
    }
    
    func on(_ event: Event<E>) {
        self.synchronizedOn(event)
    }

    func _synchronized_on(_ event: Event<E>) {
        switch event {
        case let .next(value):
            self._parent._latest = value
        case .completed:
            self._disposable.dispose()
        case let .error(error):
            self._parent.forwardOn(.error(error))
            self._parent.dispose()
        }
    }
}

final private class WithLatestFrom<FirstType, SecondType, ResultType>: Producer<ResultType> {
    typealias ResultSelector = (FirstType, SecondType) throws -> ResultType
    
    fileprivate let _first: Observable<FirstType>
    fileprivate let _second: Observable<SecondType>
    fileprivate let _resultSelector: ResultSelector

    init(first: Observable<FirstType>, second: Observable<SecondType>, resultSelector: @escaping ResultSelector) {
        self._first = first
        self._second = second
        self._resultSelector = resultSelector
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == ResultType {
        let sink = WithLatestFromSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}
