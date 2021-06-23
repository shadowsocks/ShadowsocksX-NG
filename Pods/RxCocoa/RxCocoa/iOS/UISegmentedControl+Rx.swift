//
//  UISegmentedControl+Rx.swift
//  RxCocoa
//
//  Created by Carlos García on 8/7/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if os(iOS) || os(tvOS)

import UIKit
import RxSwift

extension Reactive where Base: UISegmentedControl {
    /// Reactive wrapper for `selectedSegmentIndex` property.
    public var selectedSegmentIndex: ControlProperty<Int> {
        value
    }
    
    /// Reactive wrapper for `selectedSegmentIndex` property.
    public var value: ControlProperty<Int> {
        return base.rx.controlPropertyWithDefaultEvents(
            getter: { segmentedControl in
                segmentedControl.selectedSegmentIndex
            }, setter: { segmentedControl, value in
                segmentedControl.selectedSegmentIndex = value
            }
        )
    }
    
    /// Reactive wrapper for `setEnabled(_:forSegmentAt:)`
    public func enabledForSegment(at index: Int) -> Binder<Bool> {
        return Binder(self.base) { segmentedControl, segmentEnabled -> Void in
            segmentedControl.setEnabled(segmentEnabled, forSegmentAt: index)
        }
    }
    
    /// Reactive wrapper for `setTitle(_:forSegmentAt:)`
    public func titleForSegment(at index: Int) -> Binder<String?> {
        return Binder(self.base) { segmentedControl, title -> Void in
            segmentedControl.setTitle(title, forSegmentAt: index)
        }
    }
    
    /// Reactive wrapper for `setImage(_:forSegmentAt:)`
    public func imageForSegment(at index: Int) -> Binder<UIImage?> {
        return Binder(self.base) { segmentedControl, image -> Void in
            segmentedControl.setImage(image, forSegmentAt: index)
        }
    }

}

#endif
