//
//  Disposable.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 2/8/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

/// Respresents a disposable resource.
public protocol Disposable {
    /// Dispose resource.
    func dispose()
}
