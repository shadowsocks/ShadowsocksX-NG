//
//  TakeLast.swift
//  RxSwift
//
//  Created by Tomi Koskinen on 25/10/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {

    /**
     Returns a specified number of contiguous elements from the end of an observable sequence.

     This operator accumulates a buffer with a length enough to store elements count elements. Upon completion of the source sequence, this buffer is drained on the result sequence. This causes the elements to be delayed.

     - seealso: [takeLast operator on reactivex.io](http://reactivex.io/documentation/operators/takelast.html)

     - parameter count: Number of elements to take from the end of the source sequence.
     - returns: An observable sequence containing the specified number of elements from the end of the source sequence.
     */
    public func takeLast(_ count: Int)
        -> Observable<E> {
        return TakeLast(source: asObservable(), count: count)
    }
}

final fileprivate class TakeLastSink<O: ObserverType> : Sink<O>, ObserverType {
    typealias E = O.E
    typealias Parent = TakeLast<E>
    
    private let _parent: Parent
    
    private var _elements: Queue<E>
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        _parent = parent
        _elements = Queue<E>(capacity: parent._count + 1)
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<E>) {
        switch event {
        case .next(let value):
            _elements.enqueue(value)
            if _elements.count > self._parent._count {
                let _ = _elements.dequeue()
            }
        case .error:
            forwardOn(event)
            dispose()
        case .completed:
            for e in _elements {
                forwardOn(.next(e))
            }
            forwardOn(.completed)
            dispose()
        }
    }
}

final fileprivate class TakeLast<Element>: Producer<Element> {
    fileprivate let _source: Observable<Element>
    fileprivate let _count: Int
    
    init(source: Observable<Element>, count: Int) {
        if count < 0 {
            rxFatalError("count can't be negative")
        }
        _source = source
        _count = count
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        let sink = TakeLastSink(parent: self, observer: observer, cancel: cancel)
        let subscription = _source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
