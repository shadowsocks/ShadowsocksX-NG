//
//  DistinctUntilChanged.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/15/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

final class DistinctUntilChangedSink<O: ObserverType, Key>: Sink<O>, ObserverType {
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

final class DistinctUntilChanged<Element, Key>: Producer<Element> {
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
