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
        SwitchIfEmpty(source: self.asObservable(), ifEmpty: other)
    }
}

final private class SwitchIfEmpty<Element>: Producer<Element> {
    
    private let source: Observable<Element>
    private let ifEmpty: Observable<Element>
    
    init(source: Observable<Element>, ifEmpty: Observable<Element>) {
        self.source = source
        self.ifEmpty = ifEmpty
    }
    
    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == Element {
        let sink = SwitchIfEmptySink(ifEmpty: self.ifEmpty,
                                     observer: observer,
                                     cancel: cancel)
        let subscription = sink.run(self.source.asObservable())
        
        return (sink: sink, subscription: subscription)
    }
}

final private class SwitchIfEmptySink<Observer: ObserverType>: Sink<Observer>
    , ObserverType {
    typealias Element = Observer.Element
    
    private let ifEmpty: Observable<Element>
    private var isEmpty = true
    private let ifEmptySubscription = SingleAssignmentDisposable()
    
    init(ifEmpty: Observable<Element>, observer: Observer, cancel: Cancelable) {
        self.ifEmpty = ifEmpty
        super.init(observer: observer, cancel: cancel)
    }
    
    func run(_ source: Observable<Observer.Element>) -> Disposable {
        let subscription = source.subscribe(self)
        return Disposables.create(subscription, ifEmptySubscription)
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
            guard self.isEmpty else {
                self.forwardOn(.completed)
                self.dispose()
                return
            }
            let ifEmptySink = SwitchIfEmptySinkIter(parent: self)
            self.ifEmptySubscription.setDisposable(self.ifEmpty.subscribe(ifEmptySink))
        }
    }
}

final private class SwitchIfEmptySinkIter<Observer: ObserverType>
    : ObserverType {
    typealias Element = Observer.Element
    typealias Parent = SwitchIfEmptySink<Observer>
    
    private let parent: Parent

    init(parent: Parent) {
        self.parent = parent
    }
    
    func on(_ event: Event<Element>) {
        switch event {
        case .next:
            self.parent.forwardOn(event)
        case .error:
            self.parent.forwardOn(event)
            self.parent.dispose()
        case .completed:
            self.parent.forwardOn(event)
            self.parent.dispose()
        }
    }
}
