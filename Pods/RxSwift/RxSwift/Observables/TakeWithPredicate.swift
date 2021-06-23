//
//  TakeWithPredicate.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 6/7/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {
    /**
     Returns the elements from the source observable sequence until the other observable sequence produces an element.

     - seealso: [takeUntil operator on reactivex.io](http://reactivex.io/documentation/operators/takeuntil.html)

     - parameter other: Observable sequence that terminates propagation of elements of the source sequence.
     - returns: An observable sequence containing the elements of the source sequence up to the point the other sequence interrupted further propagation.
     */
    public func take<Source: ObservableType>(until other: Source)
        -> Observable<Element> {
        TakeUntil(source: self.asObservable(), other: other.asObservable())
    }

    /**
     Returns elements from an observable sequence until the specified condition is true.

     - seealso: [takeUntil operator on reactivex.io](http://reactivex.io/documentation/operators/takeuntil.html)

     - parameter predicate: A function to test each element for a condition.
     - parameter behavior: Whether or not to include the last element matching the predicate. Defaults to `exclusive`.

     - returns: An observable sequence that contains the elements from the input sequence that occur before the element at which the test passes.
     */
    public func take(until predicate: @escaping (Element) throws -> Bool,
                     behavior: TakeBehavior = .exclusive)
        -> Observable<Element> {
        TakeUntilPredicate(source: self.asObservable(),
                           behavior: behavior,
                           predicate: predicate)
    }

    /**
     Returns elements from an observable sequence as long as a specified condition is true.

     - seealso: [takeWhile operator on reactivex.io](http://reactivex.io/documentation/operators/takewhile.html)

     - parameter predicate: A function to test each element for a condition.
     - returns: An observable sequence that contains the elements from the input sequence that occur before the element at which the test no longer passes.
     */
    public func take(while predicate: @escaping (Element) throws -> Bool,
                     behavior: TakeBehavior = .exclusive)
        -> Observable<Element> {
        take(until: { try !predicate($0) }, behavior: behavior)
    }

    /**
     Returns the elements from the source observable sequence until the other observable sequence produces an element.

     - seealso: [takeUntil operator on reactivex.io](http://reactivex.io/documentation/operators/takeuntil.html)

     - parameter other: Observable sequence that terminates propagation of elements of the source sequence.
     - returns: An observable sequence containing the elements of the source sequence up to the point the other sequence interrupted further propagation.
     */
    @available(*, deprecated, renamed: "take(until:)")
    public func takeUntil<Source: ObservableType>(_ other: Source)
        -> Observable<Element> {
        take(until: other)
    }

    /**
     Returns elements from an observable sequence until the specified condition is true.

     - seealso: [takeUntil operator on reactivex.io](http://reactivex.io/documentation/operators/takeuntil.html)

     - parameter behavior: Whether or not to include the last element matching the predicate.
     - parameter predicate: A function to test each element for a condition.
     - returns: An observable sequence that contains the elements from the input sequence that occur before the element at which the test passes.
     */
    @available(*, deprecated, renamed: "take(until:behavior:)")
    public func takeUntil(_ behavior: TakeBehavior,
                          predicate: @escaping (Element) throws -> Bool)
        -> Observable<Element> {
        take(until: predicate, behavior: behavior)
    }

    /**
     Returns elements from an observable sequence as long as a specified condition is true.

     - seealso: [takeWhile operator on reactivex.io](http://reactivex.io/documentation/operators/takewhile.html)

     - parameter predicate: A function to test each element for a condition.
     - returns: An observable sequence that contains the elements from the input sequence that occur before the element at which the test no longer passes.
     */
    @available(*, deprecated, renamed: "take(while:)")
    public func takeWhile(_ predicate: @escaping (Element) throws -> Bool)
        -> Observable<Element> {
        take(until: { try !predicate($0) }, behavior: .exclusive)
    }
}

/// Behaviors for the take operator family.
public enum TakeBehavior {
    /// Include the last element matching the predicate.
    case inclusive

    /// Exclude the last element matching the predicate.
    case exclusive
}

// MARK: - TakeUntil Observable
final private class TakeUntilSinkOther<Other, Observer: ObserverType>
    : ObserverType
    , LockOwnerType
    , SynchronizedOnType {
    typealias Parent = TakeUntilSink<Other, Observer>
    typealias Element = Other
    
    private let parent: Parent

    var lock: RecursiveLock {
        self.parent.lock
    }
    
    fileprivate let subscription = SingleAssignmentDisposable()
    
    init(parent: Parent) {
        self.parent = parent
#if TRACE_RESOURCES
        _ = Resources.incrementTotal()
#endif
    }
    
    func on(_ event: Event<Element>) {
        self.synchronizedOn(event)
    }

    func synchronized_on(_ event: Event<Element>) {
        switch event {
        case .next:
            self.parent.forwardOn(.completed)
            self.parent.dispose()
        case .error(let e):
            self.parent.forwardOn(.error(e))
            self.parent.dispose()
        case .completed:
            self.subscription.dispose()
        }
    }
    
#if TRACE_RESOURCES
    deinit {
        _ = Resources.decrementTotal()
    }
#endif
}

final private class TakeUntilSink<Other, Observer: ObserverType>
    : Sink<Observer>
    , LockOwnerType
    , ObserverType
    , SynchronizedOnType {
    typealias Element = Observer.Element 
    typealias Parent = TakeUntil<Element, Other>
    
    private let parent: Parent
 
    let lock = RecursiveLock()
    
    
    init(parent: Parent, observer: Observer, cancel: Cancelable) {
        self.parent = parent
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<Element>) {
        self.synchronizedOn(event)
    }

    func synchronized_on(_ event: Event<Element>) {
        switch event {
        case .next:
            self.forwardOn(event)
        case .error:
            self.forwardOn(event)
            self.dispose()
        case .completed:
            self.forwardOn(event)
            self.dispose()
        }
    }
    
    func run() -> Disposable {
        let otherObserver = TakeUntilSinkOther(parent: self)
        let otherSubscription = self.parent.other.subscribe(otherObserver)
        otherObserver.subscription.setDisposable(otherSubscription)
        let sourceSubscription = self.parent.source.subscribe(self)
        
        return Disposables.create(sourceSubscription, otherObserver.subscription)
    }
}

final private class TakeUntil<Element, Other>: Producer<Element> {
    
    fileprivate let source: Observable<Element>
    fileprivate let other: Observable<Other>
    
    init(source: Observable<Element>, other: Observable<Other>) {
        self.source = source
        self.other = other
    }
    
    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == Element {
        let sink = TakeUntilSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}

// MARK: - TakeUntil Predicate
final private class TakeUntilPredicateSink<Observer: ObserverType>
    : Sink<Observer>, ObserverType {
    typealias Element = Observer.Element 
    typealias Parent = TakeUntilPredicate<Element>

    private let parent: Parent
    private var running = true

    init(parent: Parent, observer: Observer, cancel: Cancelable) {
        self.parent = parent
        super.init(observer: observer, cancel: cancel)
    }

    func on(_ event: Event<Element>) {
        switch event {
        case .next(let value):
            if !self.running {
                return
            }

            do {
                self.running = try !self.parent.predicate(value)
            } catch let e {
                self.forwardOn(.error(e))
                self.dispose()
                return
            }

            if self.running {
                self.forwardOn(.next(value))
            } else {
                if self.parent.behavior == .inclusive {
                    self.forwardOn(.next(value))
                }

                self.forwardOn(.completed)
                self.dispose()
            }
        case .error, .completed:
            self.forwardOn(event)
            self.dispose()
        }
    }

}

final private class TakeUntilPredicate<Element>: Producer<Element> {
    typealias Predicate = (Element) throws -> Bool

    private let source: Observable<Element>
    fileprivate let predicate: Predicate
    fileprivate let behavior: TakeBehavior

    init(source: Observable<Element>,
         behavior: TakeBehavior,
         predicate: @escaping Predicate) {
        self.source = source
        self.behavior = behavior
        self.predicate = predicate
    }

    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == Element {
        let sink = TakeUntilPredicateSink(parent: self, observer: observer, cancel: cancel)
        let subscription = self.source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
