//
//  ElementAt.swift
//  RxSwift
//
//  Created by Junior B. on 21/10/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//


final class ElementAtSink<O: ObserverType> : Sink<O>, ObserverType {
    typealias SourceType = O.E
    typealias Parent = ElementAt<SourceType>
    
    let _parent: Parent
    var _i: Int
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        _parent = parent
        _i = parent._index
        
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<SourceType>) {
        switch event {
        case .next(_):

            if (_i == 0) {
                forwardOn(event)
                forwardOn(.completed)
                self.dispose()
            }
            
            do {
                let _ = try decrementChecked(&_i)
            } catch(let e) {
                forwardOn(.error(e))
                dispose()
                return
            }
            
        case .error(let e):
            forwardOn(.error(e))
            self.dispose()
        case .completed:
            if (_parent._throwOnEmpty) {
                forwardOn(.error(RxError.argumentOutOfRange))
            } else {
                forwardOn(.completed)
            }
            
            self.dispose()
        }
    }
}

final class ElementAt<SourceType> : Producer<SourceType> {
    
    let _source: Observable<SourceType>
    let _throwOnEmpty: Bool
    let _index: Int
    
    init(source: Observable<SourceType>, index: Int, throwOnEmpty: Bool) {
        if index < 0 {
            rxFatalError("index can't be negative")
        }

        self._source = source
        self._index = index
        self._throwOnEmpty = throwOnEmpty
    }
    
    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == SourceType {
        let sink = ElementAtSink(parent: self, observer: observer, cancel: cancel)
        let subscription = _source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
