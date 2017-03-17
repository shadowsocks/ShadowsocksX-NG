//
//  KVORepresentable.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 11/14/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

/// Type that is KVO representable (KVO mechanism can be used to observe it).
public protocol KVORepresentable {
    /// Associated KVO type.
    associatedtype KVOType

    /// Constructs `Self` using KVO value.
    init?(KVOValue: KVOType)
}

extension KVORepresentable {
    /// Initializes `KVORepresentable` with optional value.
    init?(KVOValue: KVOType?) {
        guard let KVOValue = KVOValue else {
            return nil
        }

        self.init(KVOValue: KVOValue)
    }
}

