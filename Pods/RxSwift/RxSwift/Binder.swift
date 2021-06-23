//
//  Binder.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 9/17/17.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

/**
 Observer that enforces interface binding rules:
 * can't bind errors (in debug builds binding of errors causes `fatalError` in release builds errors are being logged)
 * ensures binding is performed on a specific scheduler

 `Binder` doesn't retain target and in case target is released, element isn't bound.
 
 By default it binds elements on main scheduler.
 */
public struct Binder<Value>: ObserverType {
    public typealias Element = Value
    
    private let binding: (Event<Value>) -> Void

    /// Initializes `Binder`
    ///
    /// - parameter target: Target object.
    /// - parameter scheduler: Scheduler used to bind the events.
    /// - parameter binding: Binding logic.
    public init<Target: AnyObject>(_ target: Target, scheduler: ImmediateSchedulerType = MainScheduler(), binding: @escaping (Target, Value) -> Void) {
        weak var weakTarget = target

        self.binding = { event in
            switch event {
            case .next(let element):
                _ = scheduler.schedule(element) { element in
                    if let target = weakTarget {
                        binding(target, element)
                    }
                    return Disposables.create()
                }
            case .error(let error):
                rxFatalErrorInDebug("Binding error: \(error)")
            case .completed:
                break
            }
        }
    }

    /// Binds next element to owner view as described in `binding`.
    public func on(_ event: Event<Value>) {
        self.binding(event)
    }

    /// Erases type of observer.
    ///
    /// - returns: type erased observer.
    public func asObserver() -> AnyObserver<Value> {
        AnyObserver(eventHandler: self.on)
    }
}
