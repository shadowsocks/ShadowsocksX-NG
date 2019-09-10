//
//  RxCollectionViewDataSourcePrefetchingProxy.swift
//  RxCocoa
//
//  Created by Rowan Livingstone on 2/15/18.
//  Copyright © 2018 Krunoslav Zaher. All rights reserved.
//

#if os(iOS) || os(tvOS)

import UIKit
import RxSwift

@available(iOS 10.0, tvOS 10.0, *)
extension UICollectionView: HasPrefetchDataSource {
    public typealias PrefetchDataSource = UICollectionViewDataSourcePrefetching
}

@available(iOS 10.0, tvOS 10.0, *)
fileprivate let collectionViewPrefetchDataSourceNotSet = CollectionViewPrefetchDataSourceNotSet()

@available(iOS 10.0, tvOS 10.0, *)
fileprivate final class CollectionViewPrefetchDataSourceNotSet
    : NSObject
    , UICollectionViewDataSourcePrefetching {

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {}

}

@available(iOS 10.0, tvOS 10.0, *)
open class RxCollectionViewDataSourcePrefetchingProxy
    : DelegateProxy<UICollectionView, UICollectionViewDataSourcePrefetching>
    , DelegateProxyType
    , UICollectionViewDataSourcePrefetching {

    /// Typed parent object.
    public weak private(set) var collectionView: UICollectionView?

    /// - parameter collectionView: Parent object for delegate proxy.
    public init(collectionView: ParentObject) {
        self.collectionView = collectionView
        super.init(parentObject: collectionView, delegateProxy: RxCollectionViewDataSourcePrefetchingProxy.self)
    }

    // Register known implementations
    public static func registerKnownImplementations() {
        self.register { RxCollectionViewDataSourcePrefetchingProxy(collectionView: $0) }
    }

    fileprivate var _prefetchItemsPublishSubject: PublishSubject<[IndexPath]>?

    /// Optimized version used for observing prefetch items callbacks.
    internal var prefetchItemsPublishSubject: PublishSubject<[IndexPath]> {
        if let subject = _prefetchItemsPublishSubject {
            return subject
        }

        let subject = PublishSubject<[IndexPath]>()
        _prefetchItemsPublishSubject = subject

        return subject
    }

    private weak var _requiredMethodsPrefetchDataSource: UICollectionViewDataSourcePrefetching? = collectionViewPrefetchDataSourceNotSet

    // MARK: delegate

    /// Required delegate method implementation.
    public func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        if let subject = _prefetchItemsPublishSubject {
            subject.on(.next(indexPaths))
        }

        (_requiredMethodsPrefetchDataSource ?? collectionViewPrefetchDataSourceNotSet).collectionView(collectionView, prefetchItemsAt: indexPaths)
    }

    /// For more information take a look at `DelegateProxyType`.
    open override func setForwardToDelegate(_ forwardToDelegate: UICollectionViewDataSourcePrefetching?, retainDelegate: Bool) {
        _requiredMethodsPrefetchDataSource = forwardToDelegate ?? collectionViewPrefetchDataSourceNotSet
        super.setForwardToDelegate(forwardToDelegate, retainDelegate: retainDelegate)
    }

    deinit {
        if let subject = _prefetchItemsPublishSubject {
            subject.on(.completed)
        }
    }

}

#endif
