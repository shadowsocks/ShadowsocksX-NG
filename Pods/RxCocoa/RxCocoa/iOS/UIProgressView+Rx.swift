//
//  UIProgressView+Rx.swift
//  RxCocoa
//
//  Created by Samuel Bae on 2/27/16.
//  Copyright © 2016 Krunoslav Zaher. All rights reserved.
//

#if os(iOS) || os(tvOS)

import RxSwift
import UIKit

extension Reactive where Base: UIProgressView {

    /// Bindable sink for `progress` property
    public var progress: Binder<Float> {
        return Binder(self.base) { progressView, progress in
            progressView.progress = progress
        }
    }

}

#endif
