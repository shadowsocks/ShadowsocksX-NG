//
//  RxScrollViewDelegateProxy.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 6/19/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if os(iOS) || os(tvOS)

import RxSwift
import UIKit
    
extension UIScrollView: HasDelegate {
    public typealias Delegate = UIScrollViewDelegate
}

/// For more information take a look at `DelegateProxyType`.
open class RxScrollViewDelegateProxy
    : DelegateProxy<UIScrollView, UIScrollViewDelegate>
    , DelegateProxyType {

    /// Typed parent object.
    public weak private(set) var scrollView: UIScrollView?

    /// - parameter scrollView: Parent object for delegate proxy.
    public init(scrollView: ParentObject) {
        self.scrollView = scrollView
        super.init(parentObject: scrollView, delegateProxy: RxScrollViewDelegateProxy.self)
    }

    // Register known implementations
    public static func registerKnownImplementations() {
        self.register { RxScrollViewDelegateProxy(scrollView: $0) }
        self.register { RxTableViewDelegateProxy(tableView: $0) }
        self.register { RxCollectionViewDelegateProxy(collectionView: $0) }
        self.register { RxTextViewDelegateProxy(textView: $0) }
    }

    private var _contentOffsetBehaviorSubject: BehaviorSubject<CGPoint>?
    private var _contentOffsetPublishSubject: PublishSubject<()>?

    /// Optimized version used for observing content offset changes.
    internal var contentOffsetBehaviorSubject: BehaviorSubject<CGPoint> {
        if let subject = _contentOffsetBehaviorSubject {
            return subject
        }

        let subject = BehaviorSubject<CGPoint>(value: self.scrollView?.contentOffset ?? CGPoint.zero)
        _contentOffsetBehaviorSubject = subject

        return subject
    }

    /// Optimized version used for observing content offset changes.
    internal var contentOffsetPublishSubject: PublishSubject<()> {
        if let subject = _contentOffsetPublishSubject {
            return subject
        }

        let subject = PublishSubject<()>()
        _contentOffsetPublishSubject = subject

        return subject
    }
    
    deinit {
        if let subject = _contentOffsetBehaviorSubject {
            subject.on(.completed)
        }

        if let subject = _contentOffsetPublishSubject {
            subject.on(.completed)
        }
    }
}

extension RxScrollViewDelegateProxy: UIScrollViewDelegate {
    /// For more information take a look at `DelegateProxyType`.
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if let subject = _contentOffsetBehaviorSubject {
            subject.on(.next(scrollView.contentOffset))
        }
        if let subject = _contentOffsetPublishSubject {
            subject.on(.next(()))
        }
        self._forwardToDelegate?.scrollViewDidScroll?(scrollView)
    }
}

#endif
