//
//  UICollectionView+Rx.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 4/2/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if os(iOS) || os(tvOS)

import RxSwift
import UIKit

// Items

extension Reactive where Base: UICollectionView {

    /**
    Binds sequences of elements to collection view items.
    
    - parameter source: Observable sequence of items.
    - parameter cellFactory: Transform between sequence elements and view cells.
    - returns: Disposable object that can be used to unbind.
     
     Example
    
         let items = Observable.just([
             1,
             2,
             3
         ])

         items
         .bind(to: collectionView.rx.items) { (collectionView, row, element) in
            let indexPath = IndexPath(row: row, section: 0)
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Cell", for: indexPath) as! NumberCell
             cell.value?.text = "\(element) @ \(row)"
             return cell
         }
         .disposed(by: disposeBag)
    */
    public func items<Sequence: Swift.Sequence, Source: ObservableType>
        (_ source: Source)
        -> (_ cellFactory: @escaping (UICollectionView, Int, Sequence.Element) -> UICollectionViewCell)
        -> Disposable where Source.Element == Sequence {
        return { cellFactory in
            let dataSource = RxCollectionViewReactiveArrayDataSourceSequenceWrapper<Sequence>(cellFactory: cellFactory)
            return self.items(dataSource: dataSource)(source)
        }
        
    }
    
    /**
    Binds sequences of elements to collection view items.
    
    - parameter cellIdentifier: Identifier used to dequeue cells.
    - parameter source: Observable sequence of items.
    - parameter configureCell: Transform between sequence elements and view cells.
    - parameter cellType: Type of collection view cell.
    - returns: Disposable object that can be used to unbind.
     
     Example

         let items = Observable.just([
             1,
             2,
             3
         ])

         items
             .bind(to: collectionView.rx.items(cellIdentifier: "Cell", cellType: NumberCell.self)) { (row, element, cell) in
                cell.value?.text = "\(element) @ \(row)"
             }
             .disposed(by: disposeBag)
    */
    public func items<Sequence: Swift.Sequence, Cell: UICollectionViewCell, Source: ObservableType>
        (cellIdentifier: String, cellType: Cell.Type = Cell.self)
        -> (_ source: Source)
        -> (_ configureCell: @escaping (Int, Sequence.Element, Cell) -> Void)
        -> Disposable where Source.Element == Sequence {
        return { source in
            return { configureCell in
                let dataSource = RxCollectionViewReactiveArrayDataSourceSequenceWrapper<Sequence> { cv, i, item in
                    let indexPath = IndexPath(item: i, section: 0)
                    let cell = cv.dequeueReusableCell(withReuseIdentifier: cellIdentifier, for: indexPath) as! Cell
                    configureCell(i, item, cell)
                    return cell
                }
                    
                return self.items(dataSource: dataSource)(source)
            }
        }
    }

    
    /**
    Binds sequences of elements to collection view items using a custom reactive data used to perform the transformation.
    
    - parameter dataSource: Data source used to transform elements to view cells.
    - parameter source: Observable sequence of items.
    - returns: Disposable object that can be used to unbind.
     
     Example
     
         let dataSource = RxCollectionViewSectionedReloadDataSource<SectionModel<String, Double>>()

         let items = Observable.just([
             SectionModel(model: "First section", items: [
                 1.0,
                 2.0,
                 3.0
             ]),
             SectionModel(model: "Second section", items: [
                 1.0,
                 2.0,
                 3.0
             ]),
             SectionModel(model: "Third section", items: [
                 1.0,
                 2.0,
                 3.0
             ])
         ])

         dataSource.configureCell = { (dataSource, cv, indexPath, element) in
             let cell = cv.dequeueReusableCell(withReuseIdentifier: "Cell", for: indexPath) as! NumberCell
             cell.value?.text = "\(element) @ row \(indexPath.row)"
             return cell
         }

         items
            .bind(to: collectionView.rx.items(dataSource: dataSource))
            .disposed(by: disposeBag)
    */
    public func items<
            DataSource: RxCollectionViewDataSourceType & UICollectionViewDataSource,
            Source: ObservableType>
        (dataSource: DataSource)
        -> (_ source: Source)
        -> Disposable where DataSource.Element == Source.Element
          {
        return { source in
            // This is called for side effects only, and to make sure delegate proxy is in place when
            // data source is being bound.
            // This is needed because theoretically the data source subscription itself might
            // call `self.rx.delegate`. If that happens, it might cause weird side effects since
            // setting data source will set delegate, and UICollectionView might get into a weird state.
            // Therefore it's better to set delegate proxy first, just to be sure.
            _ = self.delegate
            // Strong reference is needed because data source is in use until result subscription is disposed
            return source.subscribeProxyDataSource(ofObject: self.base, dataSource: dataSource, retainDataSource: true) { [weak collectionView = self.base] (_: RxCollectionViewDataSourceProxy, event) -> Void in
                guard let collectionView = collectionView else {
                    return
                }
                dataSource.collectionView(collectionView, observedEvent: event)
            }
        }
    }
}

extension Reactive where Base: UICollectionView {
    public typealias DisplayCollectionViewCellEvent = (cell: UICollectionViewCell, at: IndexPath)
    public typealias DisplayCollectionViewSupplementaryViewEvent = (supplementaryView: UICollectionReusableView, elementKind: String, at: IndexPath)

    /// Reactive wrapper for `dataSource`.
    ///
    /// For more information take a look at `DelegateProxyType` protocol documentation.
    public var dataSource: DelegateProxy<UICollectionView, UICollectionViewDataSource> {
        RxCollectionViewDataSourceProxy.proxy(for: base)
    }
    
    /// Installs data source as forwarding delegate on `rx.dataSource`.
    /// Data source won't be retained.
    ///
    /// It enables using normal delegate mechanism with reactive delegate mechanism.
    ///
    /// - parameter dataSource: Data source object.
    /// - returns: Disposable object that can be used to unbind the data source.
    public func setDataSource(_ dataSource: UICollectionViewDataSource)
        -> Disposable {
        RxCollectionViewDataSourceProxy.installForwardDelegate(dataSource, retainDelegate: false, onProxyForObject: self.base)
    }
   
    /// Reactive wrapper for `delegate` message `collectionView(_:didSelectItemAtIndexPath:)`.
    public var itemSelected: ControlEvent<IndexPath> {
        let source = delegate.methodInvoked(#selector(UICollectionViewDelegate.collectionView(_:didSelectItemAt:)))
            .map { a in
                return try castOrThrow(IndexPath.self, a[1])
            }
        
        return ControlEvent(events: source)
    }

    /// Reactive wrapper for `delegate` message `collectionView(_:didDeselectItemAtIndexPath:)`.
    public var itemDeselected: ControlEvent<IndexPath> {
        let source = delegate.methodInvoked(#selector(UICollectionViewDelegate.collectionView(_:didDeselectItemAt:)))
            .map { a in
                return try castOrThrow(IndexPath.self, a[1])
        }

        return ControlEvent(events: source)
    }

    /// Reactive wrapper for `delegate` message `collectionView(_:didHighlightItemAt:)`.
    public var itemHighlighted: ControlEvent<IndexPath> {
        let source = delegate.methodInvoked(#selector(UICollectionViewDelegate.collectionView(_:didHighlightItemAt:)))
            .map { a in
                return try castOrThrow(IndexPath.self, a[1])
            }
        
        return ControlEvent(events: source)
    }

    /// Reactive wrapper for `delegate` message `collectionView(_:didUnhighlightItemAt:)`.
    public var itemUnhighlighted: ControlEvent<IndexPath> {
        let source = delegate.methodInvoked(#selector(UICollectionViewDelegate.collectionView(_:didUnhighlightItemAt:)))
            .map { a in
                return try castOrThrow(IndexPath.self, a[1])
            }
        
        return ControlEvent(events: source)
    }

    /// Reactive wrapper for `delegate` message `collectionView:willDisplay:forItemAt:`.
    public var willDisplayCell: ControlEvent<DisplayCollectionViewCellEvent> {
        let source: Observable<DisplayCollectionViewCellEvent> = self.delegate.methodInvoked(#selector(UICollectionViewDelegate.collectionView(_:willDisplay:forItemAt:)))
            .map { a in
                return (try castOrThrow(UICollectionViewCell.self, a[1]), try castOrThrow(IndexPath.self, a[2]))
            }
        
        return ControlEvent(events: source)
    }

    /// Reactive wrapper for `delegate` message `collectionView(_:willDisplaySupplementaryView:forElementKind:at:)`.
    public var willDisplaySupplementaryView: ControlEvent<DisplayCollectionViewSupplementaryViewEvent> {
        let source: Observable<DisplayCollectionViewSupplementaryViewEvent> = self.delegate.methodInvoked(#selector(UICollectionViewDelegate.collectionView(_:willDisplaySupplementaryView:forElementKind:at:)))
            .map { a in
                return (try castOrThrow(UICollectionReusableView.self, a[1]),
                        try castOrThrow(String.self, a[2]),
                        try castOrThrow(IndexPath.self, a[3]))
            }

        return ControlEvent(events: source)
    }

    /// Reactive wrapper for `delegate` message `collectionView:didEndDisplaying:forItemAt:`.
    public var didEndDisplayingCell: ControlEvent<DisplayCollectionViewCellEvent> {
        let source: Observable<DisplayCollectionViewCellEvent> = self.delegate.methodInvoked(#selector(UICollectionViewDelegate.collectionView(_:didEndDisplaying:forItemAt:)))
            .map { a in
                return (try castOrThrow(UICollectionViewCell.self, a[1]), try castOrThrow(IndexPath.self, a[2]))
            }

        return ControlEvent(events: source)
    }

    /// Reactive wrapper for `delegate` message `collectionView(_:didEndDisplayingSupplementaryView:forElementOfKind:at:)`.
    public var didEndDisplayingSupplementaryView: ControlEvent<DisplayCollectionViewSupplementaryViewEvent> {
        let source: Observable<DisplayCollectionViewSupplementaryViewEvent> = self.delegate.methodInvoked(#selector(UICollectionViewDelegate.collectionView(_:didEndDisplayingSupplementaryView:forElementOfKind:at:)))
            .map { a in
                return (try castOrThrow(UICollectionReusableView.self, a[1]),
                        try castOrThrow(String.self, a[2]),
                        try castOrThrow(IndexPath.self, a[3]))
            }

        return ControlEvent(events: source)
    }
    
    /// Reactive wrapper for `delegate` message `collectionView(_:didSelectItemAtIndexPath:)`.
    ///
    /// It can be only used when one of the `rx.itemsWith*` methods is used to bind observable sequence,
    /// or any other data source conforming to `SectionedViewDataSourceType` protocol.
    ///
    /// ```
    ///     collectionView.rx.modelSelected(MyModel.self)
    ///        .map { ...
    /// ```
    public func modelSelected<T>(_ modelType: T.Type) -> ControlEvent<T> {
        let source: Observable<T> = itemSelected.flatMap { [weak view = self.base as UICollectionView] indexPath -> Observable<T> in
            guard let view = view else {
                return Observable.empty()
            }

            return Observable.just(try view.rx.model(at: indexPath))
        }
        
        return ControlEvent(events: source)
    }

    /// Reactive wrapper for `delegate` message `collectionView(_:didSelectItemAtIndexPath:)`.
    ///
    /// It can be only used when one of the `rx.itemsWith*` methods is used to bind observable sequence,
    /// or any other data source conforming to `SectionedViewDataSourceType` protocol.
    ///
    /// ```
    ///     collectionView.rx.modelDeselected(MyModel.self)
    ///        .map { ...
    /// ```
    public func modelDeselected<T>(_ modelType: T.Type) -> ControlEvent<T> {
        let source: Observable<T> = itemDeselected.flatMap { [weak view = self.base as UICollectionView] indexPath -> Observable<T> in
            guard let view = view else {
                return Observable.empty()
            }

            return Observable.just(try view.rx.model(at: indexPath))
        }

        return ControlEvent(events: source)
    }
    
    /// Synchronous helper method for retrieving a model at indexPath through a reactive data source
    public func model<T>(at indexPath: IndexPath) throws -> T {
        let dataSource: SectionedViewDataSourceType = castOrFatalError(self.dataSource.forwardToDelegate(), message: "This method only works in case one of the `rx.itemsWith*` methods was used.")
        
        let element = try dataSource.model(at: indexPath)

        return try castOrThrow(T.self, element)
    }
}

@available(iOS 10.0, tvOS 10.0, *)
extension Reactive where Base: UICollectionView {

    /// Reactive wrapper for `prefetchDataSource`.
    ///
    /// For more information take a look at `DelegateProxyType` protocol documentation.
    public var prefetchDataSource: DelegateProxy<UICollectionView, UICollectionViewDataSourcePrefetching> {
        RxCollectionViewDataSourcePrefetchingProxy.proxy(for: base)
    }

    /**
     Installs prefetch data source as forwarding delegate on `rx.prefetchDataSource`.
     Prefetch data source won't be retained.

     It enables using normal delegate mechanism with reactive delegate mechanism.

     - parameter prefetchDataSource: Prefetch data source object.
     - returns: Disposable object that can be used to unbind the data source.
     */
    public func setPrefetchDataSource(_ prefetchDataSource: UICollectionViewDataSourcePrefetching)
        -> Disposable {
            return RxCollectionViewDataSourcePrefetchingProxy.installForwardDelegate(prefetchDataSource, retainDelegate: false, onProxyForObject: self.base)
    }

    /// Reactive wrapper for `prefetchDataSource` message `collectionView(_:prefetchItemsAt:)`.
    public var prefetchItems: ControlEvent<[IndexPath]> {
        let source = RxCollectionViewDataSourcePrefetchingProxy.proxy(for: base).prefetchItemsPublishSubject
        return ControlEvent(events: source)
    }

    /// Reactive wrapper for `prefetchDataSource` message `collectionView(_:cancelPrefetchingForItemsAt:)`.
    public var cancelPrefetchingForItems: ControlEvent<[IndexPath]> {
        let source = prefetchDataSource.methodInvoked(#selector(UICollectionViewDataSourcePrefetching.collectionView(_:cancelPrefetchingForItemsAt:)))
            .map { a in
                return try castOrThrow(Array<IndexPath>.self, a[1])
        }

        return ControlEvent(events: source)
    }

}
#endif

#if os(tvOS)

extension Reactive where Base: UICollectionView {
    
    /// Reactive wrapper for `delegate` message `collectionView(_:didUpdateFocusInContext:withAnimationCoordinator:)`.
    public var didUpdateFocusInContextWithAnimationCoordinator: ControlEvent<(context: UICollectionViewFocusUpdateContext, animationCoordinator: UIFocusAnimationCoordinator)> {

        let source = delegate.methodInvoked(#selector(UICollectionViewDelegate.collectionView(_:didUpdateFocusIn:with:)))
            .map { a -> (context: UICollectionViewFocusUpdateContext, animationCoordinator: UIFocusAnimationCoordinator) in
                let context = try castOrThrow(UICollectionViewFocusUpdateContext.self, a[1])
                let animationCoordinator = try castOrThrow(UIFocusAnimationCoordinator.self, a[2])
                return (context: context, animationCoordinator: animationCoordinator)
            }

        return ControlEvent(events: source)
    }
}
#endif
