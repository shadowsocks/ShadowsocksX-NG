//
//  RxPickerViewDataSourceProxy.swift
//  RxCocoa
//
//  Created by Sergey Shulga on 05/07/2017.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

#if os(iOS)

import UIKit
import RxSwift

extension UIPickerView: HasDataSource {
    public typealias DataSource = UIPickerViewDataSource
}

private let pickerViewDataSourceNotSet = PickerViewDataSourceNotSet()

final private class PickerViewDataSourceNotSet: NSObject, UIPickerViewDataSource {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        0
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        0
    }
}

/// For more information take a look at `DelegateProxyType`.
public class RxPickerViewDataSourceProxy
    : DelegateProxy<UIPickerView, UIPickerViewDataSource>
    , DelegateProxyType {

    /// Typed parent object.
    public weak private(set) var pickerView: UIPickerView?

    /// - parameter pickerView: Parent object for delegate proxy.
    public init(pickerView: ParentObject) {
        self.pickerView = pickerView
        super.init(parentObject: pickerView, delegateProxy: RxPickerViewDataSourceProxy.self)
    }

    // Register known implementations
    public static func registerKnownImplementations() {
        self.register { RxPickerViewDataSourceProxy(pickerView: $0) }
    }

    private weak var _requiredMethodsDataSource: UIPickerViewDataSource? = pickerViewDataSourceNotSet

    /// For more information take a look at `DelegateProxyType`.
    public override func setForwardToDelegate(_ forwardToDelegate: UIPickerViewDataSource?, retainDelegate: Bool) {
        _requiredMethodsDataSource = forwardToDelegate ?? pickerViewDataSourceNotSet
        super.setForwardToDelegate(forwardToDelegate, retainDelegate: retainDelegate)
    }
}

// MARK: UIPickerViewDataSource

extension RxPickerViewDataSourceProxy: UIPickerViewDataSource {
    /// Required delegate method implementation.
    public func numberOfComponents(in pickerView: UIPickerView) -> Int {
        (_requiredMethodsDataSource ?? pickerViewDataSourceNotSet).numberOfComponents(in: pickerView)
    }

    /// Required delegate method implementation.
    public func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        (_requiredMethodsDataSource ?? pickerViewDataSourceNotSet).pickerView(pickerView, numberOfRowsInComponent: component)
    }
}

#endif
