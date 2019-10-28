//
//  RxCollectionViewReactiveArrayDataSource.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 6/29/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if os(iOS) || os(tvOS)

import UIKit
import RxSwift

// objc monkey business
class _RxCollectionViewReactiveArrayDataSource
    : NSObject
    , UICollectionViewDataSource {
    
    @objc(numberOfSectionsInCollectionView:)
    func numberOfSections(in: UICollectionView) -> Int {
        return 1
    }

    func _collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return 0
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return _collectionView(collectionView, numberOfItemsInSection: section)
    }

    fileprivate func _collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        rxAbstractMethod()
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        return _collectionView(collectionView, cellForItemAt: indexPath)
    }
}

class RxCollectionViewReactiveArrayDataSourceSequenceWrapper<S: Sequence>
    : RxCollectionViewReactiveArrayDataSource<S.Iterator.Element>
    , RxCollectionViewDataSourceType {
    typealias Element = S

    override init(cellFactory: @escaping CellFactory) {
        super.init(cellFactory: cellFactory)
    }
    
    func collectionView(_ collectionView: UICollectionView, observedEvent: Event<S>) {
        Binder(self) { collectionViewDataSource, sectionModels in
            let sections = Array(sectionModels)
            collectionViewDataSource.collectionView(collectionView, observedElements: sections)
        }.on(observedEvent)
    }
}


// Please take a look at `DelegateProxyType.swift`
class RxCollectionViewReactiveArrayDataSource<Element>
    : _RxCollectionViewReactiveArrayDataSource
    , SectionedViewDataSourceType {
    
    typealias CellFactory = (UICollectionView, Int, Element) -> UICollectionViewCell
    
    var itemModels: [Element]?
    
    func modelAtIndex(_ index: Int) -> Element? {
        return itemModels?[index]
    }

    func model(at indexPath: IndexPath) throws -> Any {
        precondition(indexPath.section == 0)
        guard let item = itemModels?[indexPath.item] else {
            throw RxCocoaError.itemsNotYetBound(object: self)
        }
        return item
    }
    
    var cellFactory: CellFactory
    
    init(cellFactory: @escaping CellFactory) {
        self.cellFactory = cellFactory
    }
    
    // data source
    
    override func _collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return itemModels?.count ?? 0
    }
    
    override func _collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        return cellFactory(collectionView, indexPath.item, itemModels![indexPath.item])
    }
    
    // reactive
    
    func collectionView(_ collectionView: UICollectionView, observedElements: [Element]) {
        self.itemModels = observedElements
        
        collectionView.reloadData()

        // workaround for http://stackoverflow.com/questions/39867325/ios-10-bug-uicollectionview-received-layout-attributes-for-a-cell-with-an-index
        collectionView.collectionViewLayout.invalidateLayout()
    }
}

#endif
