//
//  NSControl+Rx.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 5/31/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if os(macOS)

import Cocoa
#if !RX_NO_MODULE
import RxSwift
#endif

fileprivate var rx_value_key: UInt8 = 0
fileprivate var rx_control_events_key: UInt8 = 0

extension Reactive where Base: NSControl {

    /// Reactive wrapper for control event.
    public var controlEvent: ControlEvent<Void> {
        MainScheduler.ensureExecutingOnScheduler()

        let source = lazyInstanceObservable(&rx_control_events_key) { () -> Observable<Void> in
            Observable.create { [weak control = self.base] observer in
                MainScheduler.ensureExecutingOnScheduler()

                guard let control = control else {
                    observer.on(.completed)
                    return Disposables.create()
                }

                let observer = ControlTarget(control: control) { control in
                    observer.on(.next())
                }
                
                return observer
            }.takeUntil(self.deallocated)
        }
        
        return ControlEvent(events: source)
    }

    /// You might be wondering why the ugly `as!` casts etc, well, for some reason if
    /// Swift compiler knows C is UIControl type and optimizations are turned on, it will crash.
    static func value<C: AnyObject, T: Equatable>(_ control: C, getter: @escaping (C) -> T, setter: @escaping (C, T) -> Void) -> ControlProperty<T> {
        MainScheduler.ensureExecutingOnScheduler()

        let source = (control as! NSObject).rx.lazyInstanceObservable(&rx_value_key) { () -> Observable<T> in
            return Observable.create { [weak weakControl = control] (observer: AnyObserver<T>) in
                guard let control = weakControl else {
                    observer.on(.completed)
                    return Disposables.create()
                }

                observer.on(.next(getter(control)))

                let observer = ControlTarget(control: control as! NSControl) { _ in
                    if let control = weakControl {
                        observer.on(.next(getter(control)))
                    }
                }
                
                return observer
            }
            .distinctUntilChanged()
            .takeUntil((control as! NSObject).rx.deallocated)
        }

        let bindingObserver = UIBindingObserver(UIElement: control, binding: setter)

        return ControlProperty(values: source, valueSink: bindingObserver)
    }

    /// Bindable sink for `enabled` property.
    public var isEnabled: UIBindingObserver<Base, Bool> {
        return UIBindingObserver(UIElement: self.base) { (owner, value) in
            owner.isEnabled = value
        }
    }
}

#endif
