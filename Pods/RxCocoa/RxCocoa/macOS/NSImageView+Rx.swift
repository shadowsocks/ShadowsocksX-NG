//
//  NSImageView+Rx.swift
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

extension Reactive where Base: NSImageView {
   
    /// Bindable sink for `image` property.
    public var image: UIBindingObserver<Base, NSImage?> {
        return image(transitionType: nil)
    }
    
    /// Bindable sink for `image` property.
    ///
    /// - parameter transitionType: Optional transition type while setting the image (kCATransitionFade, kCATransitionMoveIn, ...)
    public func image(transitionType: String? = nil) -> UIBindingObserver<Base, NSImage?> {
        return UIBindingObserver(UIElement: self.base) { control, value in
            if let transitionType = transitionType {
                if value != nil {
                    let transition = CATransition()
                    transition.duration = 0.25
                    transition.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
                    transition.type = transitionType
                    control.layer?.add(transition, forKey: kCATransition)
                }
            }
            else {
                control.layer?.removeAllAnimations()
            }
            control.image = value
        }
    }
}

#endif
