//
//  SingleAsync.swift
//  RxSwift
//
//  Created by Junior B. on 09/11/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {

    /**
     The single operator is similar to first, but throws a `RxError.noElements` or `RxError.moreThanOneElement`
     if the source Observable does not emit exactly one element before successfully completing.

     - seealso: [single operator on reactivex.io](http://reactivex.io/documentation/operators/first.html)

     - returns: An observable sequence that emits a single element or throws an exception if more (or none) of them are emitted.
     */
    public func single()
        -> Observable<E> {
        return SingleAsync(source: asObservable())
    }

    /**
     The single operator is similar to first, but throws a `RxError.NoElements` or `RxError.MoreThanOneElement`
     if the source Observable does not emit exactly one element before successfully completing.

     - seealso: [single operator on reactivex.io](http://reactivex.io/documentation/operators/first.html)

     - parameter predicate: A function to test each source element for a condition.
     - returns: An observable sequence that emits a single element or throws an exception if more (or none) of them are emitted.
     */
    public func single(_ predicate: @escaping (E) throws -> Bool)
        -> Observable<E> {
        return SingleAsync(source: asObservable(), predicate: predicate)
    }
}

fileprivate final class SingleAsyncSink<O: ObserverType> : Sink<O>, ObserverType {
    typealias ElementType = O.E
    typealias Parent = SingleAsync<ElementType>
    typealias E = ElementType
    
    private let _parent: Parent
    private var _seenValue: Bool = false
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        _parent = parent
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<E>) {
        switch event {
        case .next(let value):
            do {
                let forward = try _parent._predicate?(value) ?? true
                if !forward {
                    return
                }
            }
            catch let error {
                forwardOn(.error(error as Swift.Error))
                dispose()
                return
            }

            if _seenValue {
                forwardOn(.error(RxError.moreThanOneElement))
                dispose()
                return
            }

            _seenValue = true
            forwardOn(.next(value))
        case .error:
            forwardOn(event)
            dispose()
        case .completed:
            if (_seenValue) {
                forwardOn(.completed)
            } else {
                forwardOn(.error(RxError.noElements))
            }
            dispose()
        }
    }
}

final class SingleAsync<Element>: Producer<Element> {
    typealias Predicate = (Element) throws -> Bool
    
    fileprivate let _source: Observable<Element>
    fileprivate let _predicate: Predicate?
    
    init(source: Observable<Element>, predicate: Predicate? = nil) {
        _source = source
        _predicate = predicate
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        let sink = SingleAsyncSink(parent: self, observer: observer, cancel: cancel)
        let subscription = _source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
