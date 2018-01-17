//
//  ToArray.swift
//  RxSwift
//
//  Created by Junior B. on 20/10/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//


extension ObservableType {

    /**
    Converts an Observable into another Observable that emits the whole sequence as a single array and then terminates.
    
    For aggregation behavior see `reduce`.

    - seealso: [toArray operator on reactivex.io](http://reactivex.io/documentation/operators/to.html)
    
    - returns: An observable sequence containing all the emitted elements as array.
    */
    public func toArray()
        -> Observable<[E]> {
        return ToArray(source: self.asObservable())
    }
}

final fileprivate class ToArraySink<SourceType, O: ObserverType> : Sink<O>, ObserverType where O.E == [SourceType] {
    typealias Parent = ToArray<SourceType>
    
    let _parent: Parent
    var _list = Array<SourceType>()
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        _parent = parent
        
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<SourceType>) {
        switch event {
        case .next(let value):
            self._list.append(value)
        case .error(let e):
            forwardOn(.error(e))
            self.dispose()
        case .completed:
            forwardOn(.next(_list))
            forwardOn(.completed)
            self.dispose()
        }
    }
}

final fileprivate class ToArray<SourceType> : Producer<[SourceType]> {
    let _source: Observable<SourceType>

    init(source: Observable<SourceType>) {
        _source = source
    }
    
    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == [SourceType] {
        let sink = ToArraySink(parent: self, observer: observer, cancel: cancel)
        let subscription = _source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
