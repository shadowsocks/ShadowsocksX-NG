//
//  UISlider+Rx.swift
//  RxCocoa
//
//  Created by Alexander van der Werff on 28/05/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if os(iOS)

import RxSwift
import UIKit

extension Reactive where Base: UISlider {
    
    /// Reactive wrapper for `value` property.
    public var value: ControlProperty<Float> {
        return base.rx.controlPropertyWithDefaultEvents(
            getter: { slider in
                slider.value
            }, setter: { slider, value in
                slider.value = value
            }
        )
    }
    
}

#endif
