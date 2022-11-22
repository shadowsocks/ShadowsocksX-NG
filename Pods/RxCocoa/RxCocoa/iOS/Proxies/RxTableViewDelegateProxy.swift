//
//  RxTableViewDelegateProxy.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 6/15/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if os(iOS) || os(tvOS)

import UIKit
import RxSwift

/// For more information take a look at `DelegateProxyType`.
open class RxTableViewDelegateProxy
    : RxScrollViewDelegateProxy {

    /// Typed parent object.
    public weak private(set) var tableView: UITableView?

    /// - parameter tableView: Parent object for delegate proxy.
    public init(tableView: UITableView) {
        self.tableView = tableView
        super.init(scrollView: tableView)
    }

}

extension RxTableViewDelegateProxy: UITableViewDelegate {}

#endif
