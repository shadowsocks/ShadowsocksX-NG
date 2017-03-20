//
//  NSButton+Rx.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 5/17/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if os(macOS)

#if !RX_NO_MODULE
import RxSwift
#endif
import Cocoa

extension Reactive where Base: NSButton {
    
    /// Reactive wrapper for control event.
    public var tap: ControlEvent<Void> {
        return controlEvent
    }

    /// Reactive wrapper for `state` property`.
    public var state: ControlProperty<Int> {
        return NSButton.rx.value(
            base,
            getter: { control in
                return control.state
            }, setter: { control, state in
                control.state = state
            }
        )
    }
}

#endif
