//
//  UIStepper+Rx.swift
//  RxCocoa
//
//  Created by Yuta ToKoRo on 9/1/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if os(iOS)

import UIKit
import RxSwift

extension Reactive where Base: UIStepper {
    
    /// Reactive wrapper for `value` property.
    public var value: ControlProperty<Double> {
        return base.rx.controlPropertyWithDefaultEvents(
            getter: { stepper in
                stepper.value
            }, setter: { stepper, value in
                stepper.value = value
            }
        )
    }

    /// Reactive wrapper for `stepValue` property.
    public var stepValue: Binder<Double> {
        return Binder(self.base) { stepper, value in
            stepper.stepValue = value
        }
    }
    
}

#endif

