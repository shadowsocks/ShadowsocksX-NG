//
//  SwitchIfEmpty.swift
//  RxSwift
//
//  Created by sergdort on 23/12/2016.
//  Copyright © 2016 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {
    /**
     Returns the elements of the specified sequence or `switchTo` sequence if the sequence is empty.

     - seealso: [DefaultIfEmpty operator on reactivex.io](http://reactivex.io/documentation/operators/defaultifempty.html)

     - parameter switchTo: Observable sequence being returned when source sequence is empty.
     - returns: Observable sequence that contains elements from switchTo sequence if source is empty, otherwise returns source sequence elements.
     */
    public func ifEmpty(switchTo other: Observable<Element>) -> Observable<Element> {
        return SwitchIfEmpty(source: self.asObservable(), ifEmpty: other)
    }
}

final private class SwitchIfEmpty<Element>: Producer<Element> {
    
    private let _source: Observable<Element>
    private let _ifEmpty: Observable<Element>
    
    init(source: Observable<Element>, ifEmpty: Observable<Element>) {
        self._source = source
        self._ifEmpty = ifEmpty
    }
    
    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == Element {
        let sink = SwitchIfEmptySink(ifEmpty: self._ifEmpty,
                                     observer: observer,
                                     cancel: cancel)
        let subscription = sink.run(self._source.asObservable())
        
        return (sink: sink, subscription: subscription)
    }
}

final private class SwitchIfEmptySink<Observer: ObserverType>: Sink<Observer>
    , ObserverType {
    typealias Element = Observer.Element
    
    private let _ifEmpty: Observable<Element>
    private var _isEmpty = true
    private let _ifEmptySubscription = SingleAssignmentDisposable()
    
    init(ifEmpty: Observable<Element>, observer: Observer, cancel: Cancelable) {
        self._ifEmpty = ifEmpty
        super.init(observer: observer, cancel: cancel)
    }
    
    func run(_ source: Observable<Observer.Element>) -> Disposable {
        let subscription = source.subscribe(self)
        return Disposables.create(subscription, _ifEmptySubscription)
    }
    
    func on(_ event: Event<Element>) {
        switch event {
        case .next:
            self._isEmpty = false
            self.forwardOn(event)
        case .error:
            self.forwardOn(event)
            self.dispose()
        case .completed:
            guard self._isEmpty else {
                self.forwardOn(.completed)
                self.dispose()
                return
            }
            let ifEmptySink = SwitchIfEmptySinkIter(parent: self)
            self._ifEmptySubscription.setDisposable(self._ifEmpty.subscribe(ifEmptySink))
        }
    }
}

final private class SwitchIfEmptySinkIter<Observer: ObserverType>
    : ObserverType {
    typealias Element = Observer.Element
    typealias Parent = SwitchIfEmptySink<Observer>
    
    private let _parent: Parent

    init(parent: Parent) {
        self._parent = parent
    }
    
    func on(_ event: Event<Element>) {
        switch event {
        case .next:
            self._parent.forwardOn(event)
        case .error:
            self._parent.forwardOn(event)
            self._parent.dispose()
        case .completed:
            self._parent.forwardOn(event)
            self._parent.dispose()
        }
    }
}
