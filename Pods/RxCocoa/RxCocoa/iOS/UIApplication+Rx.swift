//
//  UIApplication+Rx.swift
//  RxCocoa
//
//  Created by Mads Bøgeskov on 18/01/16.
//  Copyright © 2016 Krunoslav Zaher. All rights reserved.
//

#if os(iOS)

    import UIKit
    import RxSwift

    extension Reactive where Base: UIApplication {
        
        /// Bindable sink for `networkActivityIndicatorVisible`.
        public var isNetworkActivityIndicatorVisible: Binder<Bool> {
            return Binder(self.base) { application, active in
                application.isNetworkActivityIndicatorVisible = active
            }
        }
    }
#endif

