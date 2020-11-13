//
//  DistinctUntilChanged.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/15/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType where Element: Equatable {

    /**
     Returns an observable sequence that contains only distinct contiguous elements according to equality operator.

     - seealso: [distinct operator on reactivex.io](http://reactivex.io/documentation/operators/distinct.html)

     - returns: An observable sequence only containing the distinct contiguous elements, based on equality operator, from the source sequence.
     */
    public func distinctUntilChanged()
        -> Observable<Element> {
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
    public func distinctUntilChanged<Key: Equatable>(_ keySelector: @escaping (Element) throws -> Key)
        -> Observable<Element> {
            return self.distinctUntilChanged(keySelector, comparer: { $0 == $1 })
    }

    /**
     Returns an observable sequence that contains only distinct contiguous elements according to the `comparer`.

     - seealso: [distinct operator on reactivex.io](http://reactivex.io/documentation/operators/distinct.html)

     - parameter comparer: Equality comparer for computed key values.
     - returns: An observable sequence only containing the distinct contiguous elements, based on `comparer`, from the source sequence.
     */
    public func distinctUntilChanged(_ comparer: @escaping (Element, Element) throws -> Bool)
        -> Observable<Element> {
            return self.distinctUntilChanged({ $0 }, comparer: comparer)
    }

    /**
     Returns an observable sequence that contains only distinct contiguous elements according to the keySelector and the comparer.

     - seealso: [distinct operator on reactivex.io](http://reactivex.io/documentation/operators/distinct.html)

     - parameter keySelector: A function to compute the comparison key for each element.
     - parameter comparer: Equality comparer for computed key values.
     - returns: An observable sequence only containing the distinct contiguous elements, based on a computed key value and the comparer, from the source sequence.
     */
    public func distinctUntilChanged<K>(_ keySelector: @escaping (Element) throws -> K, comparer: @escaping (K, K) throws -> Bool)
        -> Observable<Element> {
            return DistinctUntilChanged(source: self.asObservable(), selector: keySelector, comparer: comparer)
    }
}

final private class DistinctUntilChangedSink<Observer: ObserverType, Key>: Sink<Observer>, ObserverType {
    typealias Element = Observer.Element 
    
    private let _parent: DistinctUntilChanged<Element, Key>
    private var _currentKey: Key?
    
    init(parent: DistinctUntilChanged<Element, Key>, observer: Observer, cancel: Cancelable) {
        self._parent = parent
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<Element>) {
        switch event {
        case .next(let value):
            do {
                let key = try self._parent._selector(value)
                var areEqual = false
                if let currentKey = self._currentKey {
                    areEqual = try self._parent._comparer(currentKey, key)
                }
                
                if areEqual {
                    return
                }
                
                self._currentKey = key
                
                self.forwardOn(event)
            }
            catch let error {
                self.forwardOn(.error(error))
                self.dispose()
            }
        case .error, .completed:
            self.forwardOn(event)
            self.dispose()
        }
    }
}

final private class DistinctUntilChanged<Element, Key>: Producer<Element> {
    typealias KeySelector = (Element) throws -> Key
    typealias EqualityComparer = (Key, Key) throws -> Bool
    
    private let _source: Observable<Element>
    fileprivate let _selector: KeySelector
    fileprivate let _comparer: EqualityComparer
    
    init(source: Observable<Element>, selector: @escaping KeySelector, comparer: @escaping EqualityComparer) {
        self._source = source
        self._selector = selector
        self._comparer = comparer
    }
    
    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == Element {
        let sink = DistinctUntilChangedSink(parent: self, observer: observer, cancel: cancel)
        let subscription = self._source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
