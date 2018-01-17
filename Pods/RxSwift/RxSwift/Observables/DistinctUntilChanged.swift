//
//  DistinctUntilChanged.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/15/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType where E: Equatable {

    /**
     Returns an observable sequence that contains only distinct contiguous elements according to equality operator.

     - seealso: [distinct operator on reactivex.io](http://reactivex.io/documentation/operators/distinct.html)

     - returns: An observable sequence only containing the distinct contiguous elements, based on equality operator, from the source sequence.
     */
    public func distinctUntilChanged()
        -> Observable<E> {
            return self.distinctUntilChanged({ $0 }, comparer: { ($0 == $1) })
    }
}

extension ObservableType {
    /**
     Returns an observable sequence that contains only distinct contiguous elements according to the `keySelector`.

     - seealso: [distinct operator on reactivex.io](http://reactivex.io/documentation/operators/distinct.html)

     - parameter keySelector: A function to compute the comparison key for each element.
     - returns: An observable sequence only containing the distinct contiguous elements, based on a computed key value, from the source sequence.
     */
    public func distinctUntilChanged<K: Equatable>(_ keySelector: @escaping (E) throws -> K)
        -> Observable<E> {
            return self.distinctUntilChanged(keySelector, comparer: { $0 == $1 })
    }

    /**
     Returns an observable sequence that contains only distinct contiguous elements according to the `comparer`.

     - seealso: [distinct operator on reactivex.io](http://reactivex.io/documentation/operators/distinct.html)

     - parameter comparer: Equality comparer for computed key values.
     - returns: An observable sequence only containing the distinct contiguous elements, based on `comparer`, from the source sequence.
     */
    public func distinctUntilChanged(_ comparer: @escaping (E, E) throws -> Bool)
        -> Observable<E> {
            return self.distinctUntilChanged({ $0 }, comparer: comparer)
    }

    /**
     Returns an observable sequence that contains only distinct contiguous elements according to the keySelector and the comparer.

     - seealso: [distinct operator on reactivex.io](http://reactivex.io/documentation/operators/distinct.html)

     - parameter keySelector: A function to compute the comparison key for each element.
     - parameter comparer: Equality comparer for computed key values.
     - returns: An observable sequence only containing the distinct contiguous elements, based on a computed key value and the comparer, from the source sequence.
     */
    public func distinctUntilChanged<K>(_ keySelector: @escaping (E) throws -> K, comparer: @escaping (K, K) throws -> Bool)
        -> Observable<E> {
            return DistinctUntilChanged(source: self.asObservable(), selector: keySelector, comparer: comparer)
    }
}

final fileprivate class DistinctUntilChangedSink<O: ObserverType, Key>: Sink<O>, ObserverType {
    typealias E = O.E
    
    private let _parent: DistinctUntilChanged<E, Key>
    private var _currentKey: Key? = nil
    
    init(parent: DistinctUntilChanged<E, Key>, observer: O, cancel: Cancelable) {
        _parent = parent
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<E>) {
        switch event {
        case .next(let value):
            do {
                let key = try _parent._selector(value)
                var areEqual = false
                if let currentKey = _currentKey {
                    areEqual = try _parent._comparer(currentKey, key)
                }
                
                if areEqual {
                    return
                }
                
                _currentKey = key
                
                forwardOn(event)
            }
            catch let error {
                forwardOn(.error(error))
                dispose()
            }
        case .error, .completed:
            forwardOn(event)
            dispose()
        }
    }
}

final fileprivate class DistinctUntilChanged<Element, Key>: Producer<Element> {
    typealias KeySelector = (Element) throws -> Key
    typealias EqualityComparer = (Key, Key) throws -> Bool
    
    fileprivate let _source: Observable<Element>
    fileprivate let _selector: KeySelector
    fileprivate let _comparer: EqualityComparer
    
    init(source: Observable<Element>, selector: @escaping KeySelector, comparer: @escaping EqualityComparer) {
        _source = source
        _selector = selector
        _comparer = comparer
    }
    
    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        let sink = DistinctUntilChangedSink(parent: self, observer: observer, cancel: cancel)
        let subscription = _source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
