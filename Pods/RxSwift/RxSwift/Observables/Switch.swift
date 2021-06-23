//
//  Switch.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/12/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {
    /**
     Projects each element of an observable sequence into a new sequence of observable sequences and then
     transforms an observable sequence of observable sequences into an observable sequence producing values only from the most recent observable sequence.

     It is a combination of `map` + `switchLatest` operator

     - seealso: [flatMapLatest operator on reactivex.io](http://reactivex.io/documentation/operators/flatmap.html)

     - parameter selector: A transform function to apply to each element.
     - returns: An observable sequence whose elements are the result of invoking the transform function on each element of source producing an
     Observable of Observable sequences and that at any point in time produces the elements of the most recent inner observable sequence that has been received.
     */
    public func flatMapLatest<Source: ObservableConvertibleType>(_ selector: @escaping (Element) throws -> Source)
        -> Observable<Source.Element> {
        return FlatMapLatest(source: self.asObservable(), selector: selector)
    }

    /**
     Projects each element of an observable sequence into a new sequence of observable sequences and then
     transforms an observable sequence of observable sequences into an observable sequence producing values only from the most recent observable sequence.

     It is a combination of `map` + `switchLatest` operator

     - seealso: [flatMapLatest operator on reactivex.io](http://reactivex.io/documentation/operators/flatmap.html)

     - parameter selector: A transform function to apply to each element.
     - returns: An observable sequence whose elements are the result of invoking the transform function on each element of source producing an
     Observable of Observable sequences and that at any point in time produces the elements of the most recent inner observable sequence that has been received.
     */
    public func flatMapLatest<Source: InfallibleType>(_ selector: @escaping (Element) throws -> Source)
        -> Infallible<Source.Element> {
        return Infallible(flatMapLatest(selector))
    }
}

extension ObservableType where Element: ObservableConvertibleType {

    /**
     Transforms an observable sequence of observable sequences into an observable sequence
     producing values only from the most recent observable sequence.

     Each time a new inner observable sequence is received, unsubscribe from the
     previous inner observable sequence.

     - seealso: [switch operator on reactivex.io](http://reactivex.io/documentation/operators/switch.html)

     - returns: The observable sequence that at any point in time produces the elements of the most recent inner observable sequence that has been received.
     */
    public func switchLatest() -> Observable<Element.Element> {
        Switch(source: self.asObservable())
    }
}

private class SwitchSink<SourceType, Source: ObservableConvertibleType, Observer: ObserverType>
    : Sink<Observer>
    , ObserverType where Source.Element == Observer.Element {
    typealias Element = SourceType

    private let subscriptions: SingleAssignmentDisposable = SingleAssignmentDisposable()
    private let innerSubscription: SerialDisposable = SerialDisposable()

    let lock = RecursiveLock()
    
    // state
    fileprivate var stopped = false
    fileprivate var latest = 0
    fileprivate var hasLatest = false
    
    override init(observer: Observer, cancel: Cancelable) {
        super.init(observer: observer, cancel: cancel)
    }
    
    func run(_ source: Observable<SourceType>) -> Disposable {
        let subscription = source.subscribe(self)
        self.subscriptions.setDisposable(subscription)
        return Disposables.create(subscriptions, innerSubscription)
    }

    func performMap(_ element: SourceType) throws -> Source {
        rxAbstractMethod()
    }

    @inline(__always)
    final private func nextElementArrived(element: Element) -> (Int, Observable<Source.Element>)? {
        self.lock.lock(); defer { self.lock.unlock() }

        do {
            let observable = try self.performMap(element).asObservable()
            self.hasLatest = true
            self.latest = self.latest &+ 1
            return (self.latest, observable)
        }
        catch let error {
            self.forwardOn(.error(error))
            self.dispose()
        }

        return nil
    }

    func on(_ event: Event<Element>) {
        switch event {
        case .next(let element):
            if let (latest, observable) = self.nextElementArrived(element: element) {
                let d = SingleAssignmentDisposable()
                self.innerSubscription.disposable = d
                   
                let observer = SwitchSinkIter(parent: self, id: latest, this: d)
                let disposable = observable.subscribe(observer)
                d.setDisposable(disposable)
            }
        case .error(let error):
            self.lock.lock(); defer { self.lock.unlock() }
            self.forwardOn(.error(error))
            self.dispose()
        case .completed:
            self.lock.lock(); defer { self.lock.unlock() }
            self.stopped = true
            
            self.subscriptions.dispose()
            
            if !self.hasLatest {
                self.forwardOn(.completed)
                self.dispose()
            }
        }
    }
}

final private class SwitchSinkIter<SourceType, Source: ObservableConvertibleType, Observer: ObserverType>
    : ObserverType
    , LockOwnerType
    , SynchronizedOnType where Source.Element == Observer.Element {
    typealias Element = Source.Element
    typealias Parent = SwitchSink<SourceType, Source, Observer>
    
    private let parent: Parent
    private let id: Int
    private let this: Disposable

    var lock: RecursiveLock {
        self.parent.lock
    }

    init(parent: Parent, id: Int, this: Disposable) {
        self.parent = parent
        self.id = id
        self.this = this
    }
    
    func on(_ event: Event<Element>) {
        self.synchronizedOn(event)
    }

    func synchronized_on(_ event: Event<Element>) {
        switch event {
        case .next: break
        case .error, .completed:
            self.this.dispose()
        }
        
        if self.parent.latest != self.id {
            return
        }
       
        switch event {
        case .next:
            self.parent.forwardOn(event)
        case .error:
            self.parent.forwardOn(event)
            self.parent.dispose()
        case .completed:
            self.parent.hasLatest = false
            if self.parent.stopped {
                self.parent.forwardOn(event)
                self.parent.dispose()
            }
        }
    }
}

// MARK: Specializations

final private class SwitchIdentitySink<Source: ObservableConvertibleType, Observer: ObserverType>: SwitchSink<Source, Source, Observer>
    where Observer.Element == Source.Element {
    override init(observer: Observer, cancel: Cancelable) {
        super.init(observer: observer, cancel: cancel)
    }

    override func performMap(_ element: Source) throws -> Source {
        element
    }
}

final private class MapSwitchSink<SourceType, Source: ObservableConvertibleType, Observer: ObserverType>: SwitchSink<SourceType, Source, Observer> where Observer.Element == Source.Element {
    typealias Selector = (SourceType) throws -> Source

    private let selector: Selector

    init(selector: @escaping Selector, observer: Observer, cancel: Cancelable) {
        self.selector = selector
        super.init(observer: observer, cancel: cancel)
    }

    override func performMap(_ element: SourceType) throws -> Source {
        try self.selector(element)
    }
}

// MARK: Producers

final private class Switch<Source: ObservableConvertibleType>: Producer<Source.Element> {
    private let source: Observable<Source>
    
    init(source: Observable<Source>) {
        self.source = source
    }
    
    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == Source.Element {
        let sink = SwitchIdentitySink<Source, Observer>(observer: observer, cancel: cancel)
        let subscription = sink.run(self.source)
        return (sink: sink, subscription: subscription)
    }
}

final private class FlatMapLatest<SourceType, Source: ObservableConvertibleType>: Producer<Source.Element> {
    typealias Selector = (SourceType) throws -> Source

    private let source: Observable<SourceType>
    private let selector: Selector

    init(source: Observable<SourceType>, selector: @escaping Selector) {
        self.source = source
        self.selector = selector
    }

    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == Source.Element {
        let sink = MapSwitchSink<SourceType, Source, Observer>(selector: self.selector, observer: observer, cancel: cancel)
        let subscription = sink.run(self.source)
        return (sink: sink, subscription: subscription)
    }
}
