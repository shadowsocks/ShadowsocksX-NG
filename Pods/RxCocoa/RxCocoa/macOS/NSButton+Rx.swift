//
//  NSButton+Rx.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 5/17/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if os(macOS)

import RxSwift
import Cocoa

extension Reactive where Base: NSButton {
    
    /// Reactive wrapper for control event.
    public var tap: ControlEvent<Void> {
        return self.controlEvent
    }
    
    /// Reactive wrapper for `state` property`.
    public var state: ControlProperty<NSControl.StateValue> {
        return self.base.rx.controlProperty(
            getter: { control in
                return control.state
            }, setter: { (control: NSButton, state: NSControl.StateValue) in
                control.state = state
            }
        )
    }
}

#endif
