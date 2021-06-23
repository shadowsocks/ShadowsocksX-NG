//
//  ElementAt.swift
//  RxSwift
//
//  Created by Junior B. on 21/10/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {
    /**
     Returns a sequence emitting only element _n_ emitted by an Observable

     - seealso: [elementAt operator on reactivex.io](http://reactivex.io/documentation/operators/elementat.html)

     - parameter index: The index of the required element (starting from 0).
     - returns: An observable sequence that emits the desired element as its own sole emission.
     */
    @available(*, deprecated, renamed: "element(at:)")
    public func elementAt(_ index: Int)
        -> Observable<Element> {
        element(at: index)
    }

    /**
     Returns a sequence emitting only element _n_ emitted by an Observable

     - seealso: [elementAt operator on reactivex.io](http://reactivex.io/documentation/operators/elementat.html)

     - parameter index: The index of the required element (starting from 0).
     - returns: An observable sequence that emits the desired element as its own sole emission.
     */
    public func element(at index: Int)
        -> Observable<Element> {
        ElementAt(source: self.asObservable(), index: index, throwOnEmpty: true)
    }
}

final private class ElementAtSink<Observer: ObserverType>: Sink<Observer>, ObserverType {
    typealias SourceType = Observer.Element
    typealias Parent = ElementAt<SourceType>
    
    let parent: Parent
    var i: Int
    
    init(parent: Parent, observer: Observer, cancel: Cancelable) {
        self.parent = parent
        self.i = parent.index
        
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<SourceType>) {
        switch event {
        case .next:

            if self.i == 0 {
                self.forwardOn(event)
                self.forwardOn(.completed)
                self.dispose()
            }
            
            do {
                _ = try decrementChecked(&self.i)
            } catch let e {
                self.forwardOn(.error(e))
                self.dispose()
                return
            }
            
        case .error(let e):
            self.forwardOn(.error(e))
            self.dispose()
        case .completed:
            if self.parent.throwOnEmpty {
                self.forwardOn(.error(RxError.argumentOutOfRange))
            } else {
                self.forwardOn(.completed)
            }
            
            self.dispose()
        }
    }
}

final private class ElementAt<SourceType>: Producer<SourceType> {
    let source: Observable<SourceType>
    let throwOnEmpty: Bool
    let index: Int
    
    init(source: Observable<SourceType>, index: Int, throwOnEmpty: Bool) {
        if index < 0 {
            rxFatalError("index can't be negative")
        }

        self.source = source
        self.index = index
        self.throwOnEmpty = throwOnEmpty
    }
    
    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == SourceType {
        let sink = ElementAtSink(parent: self, observer: observer, cancel: cancel)
        let subscription = self.source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
