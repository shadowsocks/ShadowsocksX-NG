//
//  SynchronizedDisposeType.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 10/25/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

protocol SynchronizedDisposeType : class, Disposable, Lock {
    func _synchronized_dispose()
}

extension SynchronizedDisposeType {
    func synchronizedDispose() {
        lock(); defer { unlock() }
        _synchronized_dispose()
    }
}
