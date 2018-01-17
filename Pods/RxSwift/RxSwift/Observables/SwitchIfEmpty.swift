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
    public func ifEmpty(switchTo other: Observable<E>) -> Observable<E> {
        return SwitchIfEmpty(source: asObservable(), ifEmpty: other)
    }
}

final fileprivate class SwitchIfEmpty<Element>: Producer<Element> {
    
    private let _source: Observable<E>
    private let _ifEmpty: Observable<E>
    
    init(source: Observable<E>, ifEmpty: Observable<E>) {
        _source = source
        _ifEmpty = ifEmpty
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        let sink = SwitchIfEmptySink(ifEmpty: _ifEmpty,
                                     observer: observer,
                                     cancel: cancel)
        let subscription = sink.run(_source.asObservable())
        
        return (sink: sink, subscription: subscription)
    }
}

final fileprivate class SwitchIfEmptySink<O: ObserverType>: Sink<O>
    , ObserverType {
    typealias E = O.E
    
    private let _ifEmpty: Observable<E>
    private var _isEmpty = true
    private let _ifEmptySubscription = SingleAssignmentDisposable()
    
    init(ifEmpty: Observable<E>, observer: O, cancel: Cancelable) {
        _ifEmpty = ifEmpty
        super.init(observer: observer, cancel: cancel)
    }
    
    func run(_ source: Observable<O.E>) -> Disposable {
        let subscription = source.subscribe(self)
        return Disposables.create(subscription, _ifEmptySubscription)
    }
    
    func on(_ event: Event<E>) {
        switch event {
        case .next:
            _isEmpty = false
            forwardOn(event)
        case .error:
            forwardOn(event)
            dispose()
        case .completed:
            guard _isEmpty else {
                forwardOn(.completed)
                dispose()
                return
            }
            let ifEmptySink = SwitchIfEmptySinkIter(parent: self)
            _ifEmptySubscription.setDisposable(_ifEmpty.subscribe(ifEmptySink))
        }
    }
}

final fileprivate class SwitchIfEmptySinkIter<O: ObserverType>
    : ObserverType {
    typealias E = O.E
    typealias Parent = SwitchIfEmptySink<O>
    
    private let _parent: Parent

    init(parent: Parent) {
        _parent = parent
    }
    
    func on(_ event: Event<E>) {
        switch event {
        case .next:
            _parent.forwardOn(event)
        case .error:
            _parent.forwardOn(event)
            _parent.dispose()
        case .completed:
            _parent.forwardOn(event)
            _parent.dispose()
        }
    }
}
