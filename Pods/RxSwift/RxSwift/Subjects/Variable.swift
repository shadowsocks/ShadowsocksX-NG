//
//  Variable.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/28/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

/// Variable is a wrapper for `BehaviorSubject`.
///
/// Unlike `BehaviorSubject` it can't terminate with error, and when variable is deallocated
/// it will complete it's observable sequence (`asObservable`).
public final class Variable<Element> {

    public typealias E = Element
    
    private let _subject: BehaviorSubject<Element>
    
    private var _lock = SpinLock()
 
    // state
    private var _value: E

    #if DEBUG
        fileprivate var _numberOfConcurrentCalls: AtomicInt = 0
    #endif

    /// Gets or sets current value of variable.
    ///
    /// Whenever a new value is set, all the observers are notified of the change.
    ///
    /// Even if the newly set value is same as the old value, observers are still notified for change.
    public var value: E {
        get {
            _lock.lock(); defer { _lock.unlock() }
            return _value
        }
        set(newValue) {
            #if DEBUG
                if AtomicIncrement(&_numberOfConcurrentCalls) > 1 {
                    rxFatalError("Warning: Recursive call or synchronization error!")
                }

                defer {
                    _ = AtomicDecrement(&_numberOfConcurrentCalls)
                }
            #endif
            _lock.lock()
            _value = newValue
            _lock.unlock()

            _subject.on(.next(newValue))
        }
    }
    
    /// Initializes variable with initial value.
    ///
    /// - parameter value: Initial variable value.
    public init(_ value: Element) {
        _value = value
        _subject = BehaviorSubject(value: value)
    }
    
    /// - returns: Canonical interface for push style sequence
    public func asObservable() -> Observable<E> {
        return _subject
    }

    deinit {
        _subject.on(.completed)
    }
}
