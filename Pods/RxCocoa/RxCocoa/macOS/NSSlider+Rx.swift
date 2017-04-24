//
//  NSSlider+Rx.swift
//  RxCocoa
//
//  Created by Junior B. on 24/05/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if os(macOS)

#if !RX_NO_MODULE
import RxSwift
#endif
import Cocoa

extension Reactive where Base: NSSlider {
    
    /// Reactive wrapper for `value` property.
    public var value: ControlProperty<Double> {
        return NSControl.rx.value(
            base,
            getter: { control in
                return control.doubleValue
            },
            setter: { control, value in
                control.doubleValue = value
            }
        )
    }
    
}

#endif
