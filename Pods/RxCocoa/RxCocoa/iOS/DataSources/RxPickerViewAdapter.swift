//
//  RxPickerViewAdapter.swift
//  RxCocoa
//
//  Created by Sergey Shulga on 12/07/2017.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

#if os(iOS)

import UIKit
import RxSwift

class RxPickerViewArrayDataSource<T>: NSObject, UIPickerViewDataSource, SectionedViewDataSourceType {
    fileprivate var items: [T] = []
    
    func model(at indexPath: IndexPath) throws -> Any {
        guard items.indices ~= indexPath.row else {
            throw RxCocoaError.itemsNotYetBound(object: self)
        }
        return items[indexPath.row]
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return items.count
    }
}

class RxPickerViewSequenceDataSource<Sequence: Swift.Sequence>
    : RxPickerViewArrayDataSource<Sequence.Element>
    , RxPickerViewDataSourceType {
    typealias Element = Sequence

    func pickerView(_ pickerView: UIPickerView, observedEvent: Event<Sequence>) {
        Binder(self) { dataSource, items in
            dataSource.items = items
            pickerView.reloadAllComponents()
        }
        .on(observedEvent.map(Array.init))
    }
}

final class RxStringPickerViewAdapter<Sequence: Swift.Sequence>
    : RxPickerViewSequenceDataSource<Sequence>
    , UIPickerViewDelegate {
    
    typealias TitleForRow = (Int, Sequence.Element) -> String?
    private let titleForRow: TitleForRow
    
    init(titleForRow: @escaping TitleForRow) {
        self.titleForRow = titleForRow
        super.init()
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return titleForRow(row, items[row])
    }
}

final class RxAttributedStringPickerViewAdapter<Sequence: Swift.Sequence>: RxPickerViewSequenceDataSource<Sequence>, UIPickerViewDelegate {
    typealias AttributedTitleForRow = (Int, Sequence.Element) -> NSAttributedString?
    private let attributedTitleForRow: AttributedTitleForRow
    
    init(attributedTitleForRow: @escaping AttributedTitleForRow) {
        self.attributedTitleForRow = attributedTitleForRow
        super.init()
    }
    
    func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
        return attributedTitleForRow(row, items[row])
    }
}

final class RxPickerViewAdapter<Sequence: Swift.Sequence>: RxPickerViewSequenceDataSource<Sequence>, UIPickerViewDelegate {
    typealias ViewForRow = (Int, Sequence.Element, UIView?) -> UIView
    private let viewForRow: ViewForRow
    
    init(viewForRow: @escaping ViewForRow) {
        self.viewForRow = viewForRow
        super.init()
    }
    
    func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
        return viewForRow(row, items[row], view)
    }
}

#endif
