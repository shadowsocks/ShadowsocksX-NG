//
//  RxPickerViewDelegateProxy.swift
//  RxCocoa
//
//  Created by Segii Shulga on 5/12/16.
//  Copyright © 2016 Krunoslav Zaher. All rights reserved.
//

#if os(iOS)

    import RxSwift
    import UIKit

    extension UIPickerView: HasDelegate {
        public typealias Delegate = UIPickerViewDelegate
    }

    open class RxPickerViewDelegateProxy
        : DelegateProxy<UIPickerView, UIPickerViewDelegate>
        , DelegateProxyType {

        /// Typed parent object.
        public weak private(set) var pickerView: UIPickerView?

        /// - parameter pickerView: Parent object for delegate proxy.
        public init(pickerView: ParentObject) {
            self.pickerView = pickerView
            super.init(parentObject: pickerView, delegateProxy: RxPickerViewDelegateProxy.self)
        }

        // Register known implementations
        public static func registerKnownImplementations() {
            self.register { RxPickerViewDelegateProxy(pickerView: $0) }
        }
    }

    extension RxPickerViewDelegateProxy: UIPickerViewDelegate {}
#endif
