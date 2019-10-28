//
//  RxTabBarControllerDelegateProxy.swift
//  RxCocoa
//
//  Created by Yusuke Kita on 2016/12/07.
//  Copyright © 2016 Krunoslav Zaher. All rights reserved.
//

#if os(iOS) || os(tvOS)

import UIKit
import RxSwift

extension UITabBarController: HasDelegate {
    public typealias Delegate = UITabBarControllerDelegate
}

/// For more information take a look at `DelegateProxyType`.
open class RxTabBarControllerDelegateProxy
    : DelegateProxy<UITabBarController, UITabBarControllerDelegate>
    , DelegateProxyType 
    , UITabBarControllerDelegate {

    /// Typed parent object.
    public weak private(set) var tabBar: UITabBarController?

    /// - parameter tabBar: Parent object for delegate proxy.
    public init(tabBar: ParentObject) {
        self.tabBar = tabBar
        super.init(parentObject: tabBar, delegateProxy: RxTabBarControllerDelegateProxy.self)
    }

    // Register known implementations
    public static func registerKnownImplementations() {
        self.register { RxTabBarControllerDelegateProxy(tabBar: $0) }
    }
}

#endif
