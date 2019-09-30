//
//  UIAlertAction+Rx.swift
//  RxCocoa
//
//  Created by Andrew Breckenridge on 5/7/16.
//  Copyright © 2016 Krunoslav Zaher. All rights reserved.
//

#if os(iOS) || os(tvOS)

import UIKit
import RxSwift

extension Reactive where Base: UIAlertAction {

    /// Bindable sink for `enabled` property.
    public var isEnabled: Binder<Bool> {
        return Binder(self.base) { alertAction, value in
            alertAction.isEnabled = value
        }
    }
    
}
    
#endif
