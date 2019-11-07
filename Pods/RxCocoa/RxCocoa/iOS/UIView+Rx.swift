//
//  UIView+Rx.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 12/6/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if os(iOS) || os(tvOS)

import UIKit
import RxSwift

extension Reactive where Base: UIView {
    /// Bindable sink for `hidden` property.
    public var isHidden: Binder<Bool> {
        return Binder(self.base) { view, hidden in
            view.isHidden = hidden
        }
    }

    /// Bindable sink for `alpha` property.
    public var alpha: Binder<CGFloat> {
        return Binder(self.base) { view, alpha in
            view.alpha = alpha
        }
    }

    /// Bindable sink for `backgroundColor` property.
    public var backgroundColor: Binder<UIColor?> {
        return Binder(self.base) { view, color in
            view.backgroundColor = color
        }
    }

    /// Bindable sink for `isUserInteractionEnabled` property.
    public var isUserInteractionEnabled: Binder<Bool> {
        return Binder(self.base) { view, userInteractionEnabled in
            view.isUserInteractionEnabled = userInteractionEnabled
        }
    }
    
}

#endif
