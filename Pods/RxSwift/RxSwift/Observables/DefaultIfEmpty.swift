//
//  DefaultIfEmpty.swift
//  RxSwift
//
//  Created by sergdort on 23/12/2016.
//  Copyright © 2016 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {

    /**
     Emits elements from the source observable sequence, or a default element if the source observable sequence is empty.

     - seealso: [DefaultIfEmpty operator on reactivex.io](http://reactivex.io/documentation/operators/defaultifempty.html)

     - parameter default: Default element to be sent if the source does not emit any elements
     - returns: An observable sequence which emits default element end completes in case the original sequence is empty
     */
    public func ifEmpty(default: E) -> Observable<E> {
        return DefaultIfEmpty(source: self.asObservable(), default: `default`)
    }
}

final private class DefaultIfEmptySink<O: ObserverType>: Sink<O>, ObserverType {
    typealias E = O.E
    private let _default: E
    private var _isEmpty = true
    
    init(default: E, observer: O, cancel: Cancelable) {
        self._default = `default`
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<E>) {
        switch event {
        case .next:
            self._isEmpty = false
            self.forwardOn(event)
        case .error:
            self.forwardOn(event)
            self.dispose()
        case .completed:
            if self._isEmpty {
                self.forwardOn(.next(self._default))
            }
            self.forwardOn(.completed)
            self.dispose()
        }
    }
}

final private class DefaultIfEmpty<SourceType>: Producer<SourceType> {
    private let _source: Observable<SourceType>
    private let _default: SourceType
    
    init(source: Observable<SourceType>, `default`: SourceType) {
        self._source = source
        self._default = `default`
    }
    
    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == SourceType {
        let sink = DefaultIfEmptySink(default: self._default, observer: observer, cancel: cancel)
        let subscription = self._source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
