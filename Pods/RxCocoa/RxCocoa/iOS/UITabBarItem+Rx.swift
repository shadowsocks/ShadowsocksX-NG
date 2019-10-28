//
//  UITabBarItem+Rx.swift
//  RxCocoa
//
//  Created by Mateusz Derks on 04/03/16.
//  Copyright © 2016 Krunoslav Zaher. All rights reserved.
//

#if os(iOS) || os(tvOS)
    
import UIKit
import RxSwift
    
extension Reactive where Base: UITabBarItem {
    
    /// Bindable sink for `badgeValue` property.
    public var badgeValue: Binder<String?> {
        return Binder(self.base) { tabBarItem, badgeValue in
            tabBarItem.badgeValue = badgeValue
        }
    }
    
}
    
#endif
