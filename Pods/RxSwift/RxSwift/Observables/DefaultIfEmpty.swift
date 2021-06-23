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
    public func ifEmpty(default: Element) -> Observable<Element> {
        DefaultIfEmpty(source: self.asObservable(), default: `default`)
    }
}

final private class DefaultIfEmptySink<Observer: ObserverType>: Sink<Observer>, ObserverType {
    typealias Element = Observer.Element 
    private let `default`: Element
    private var isEmpty = true
    
    init(default: Element, observer: Observer, cancel: Cancelable) {
        self.default = `default`
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<Element>) {
        switch event {
        case .next:
            self.isEmpty = false
            self.forwardOn(event)
        case .error:
            self.forwardOn(event)
            self.dispose()
        case .completed:
            if self.isEmpty {
                self.forwardOn(.next(self.default))
            }
            self.forwardOn(.completed)
            self.dispose()
        }
    }
}

final private class DefaultIfEmpty<SourceType>: Producer<SourceType> {
    private let source: Observable<SourceType>
    private let `default`: SourceType
    
    init(source: Observable<SourceType>, `default`: SourceType) {
        self.source = source
        self.default = `default`
    }
    
    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == SourceType {
        let sink = DefaultIfEmptySink(default: self.default, observer: observer, cancel: cancel)
        let subscription = self.source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
