//
//  ControlProperty.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 8/28/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import RxSwift

/// Protocol that enables extension of `ControlProperty`.
public protocol ControlPropertyType : ObservableType, ObserverType {

    /// - returns: `ControlProperty` interface
    func asControlProperty() -> ControlProperty<E>
}

/**
    Trait for `Observable`/`ObservableType` that represents property of UI element.
 
    Sequence of values only represents initial control value and user initiated value changes.
    Programmatic value changes won't be reported.

    It's properties are:

    - it never fails
    - `shareReplay(1)` behavior
        - it's stateful, upon subscription (calling subscribe) last element is immediately replayed if it was produced
    - it will `Complete` sequence on control being deallocated
    - it never errors out
    - it delivers events on `MainScheduler.instance`

    **The implementation of `ControlProperty` will ensure that sequence of values is being subscribed on main scheduler
    (`subscribeOn(ConcurrentMainScheduler.instance)` behavior).**

    **It is implementor's responsibility to make sure that that all other properties enumerated above are satisfied.**

    **If they aren't, then using this trait communicates wrong properties and could potentially break someone's code.**

    **In case `values` observable sequence that is being passed into initializer doesn't satisfy all enumerated
    properties, please don't use this trait.**
*/
public struct ControlProperty<PropertyType> : ControlPropertyType {
    public typealias E = PropertyType

    let _values: Observable<PropertyType>
    let _valueSink: AnyObserver<PropertyType>

    /// Initializes control property with a observable sequence that represents property values and observer that enables
    /// binding values to property.
    ///
    /// - parameter values: Observable sequence that represents property values.
    /// - parameter valueSink: Observer that enables binding values to control property.
    /// - returns: Control property created with a observable sequence of values and an observer that enables binding values
    /// to property.
    public init<V: ObservableType, S: ObserverType>(values: V, valueSink: S) where E == V.E, E == S.E {
        self._values = values.subscribeOn(ConcurrentMainScheduler.instance)
        self._valueSink = valueSink.asObserver()
    }

    /// Subscribes an observer to control property values.
    ///
    /// - parameter observer: Observer to subscribe to property values.
    /// - returns: Disposable object that can be used to unsubscribe the observer from receiving control property values.
    public func subscribe<O: ObserverType>(_ observer: O) -> Disposable where O.E == E {
        return self._values.subscribe(observer)
    }

    /// `ControlEvent` of user initiated value changes. Every time user updates control value change event
    /// will be emitted from `changed` event.
    ///
    /// Programmatic changes to control value won't be reported.
    ///
    /// It contains all control property values except for first one.
    ///
    /// The name only implies that sequence element will be generated once user changes a value and not that
    /// adjacent sequence values need to be different (e.g. because of interaction between programmatic and user updates,
    /// or for any other reason).
    public var changed: ControlEvent<PropertyType> {
        return ControlEvent(events: self._values.skip(1))
    }

    /// - returns: `Observable` interface.
    public func asObservable() -> Observable<E> {
        return self._values
    }

    /// - returns: `ControlProperty` interface.
    public func asControlProperty() -> ControlProperty<E> {
        return self
    }

    /// Binds event to user interface.
    ///
    /// - In case next element is received, it is being set to control value.
    /// - In case error is received, DEBUG buids raise fatal error, RELEASE builds log event to standard output.
    /// - In case sequence completes, nothing happens.
    public func on(_ event: Event<E>) {
        switch event {
        case .error(let error):
            bindingError(error)
        case .next:
            self._valueSink.on(event)
        case .completed:
            self._valueSink.on(event)
        }
    }
}

extension ControlPropertyType where E == String? {
    /// Transforms control property of type `String?` into control property of type `String`.
    public var orEmpty: ControlProperty<String> {
        let original: ControlProperty<String?> = self.asControlProperty()

        let values: Observable<String> = original._values.map { $0 ?? "" }
        let valueSink: AnyObserver<String> = original._valueSink.mapObserver { $0 }
        return ControlProperty<String>(values: values, valueSink: valueSink)
    }
}
