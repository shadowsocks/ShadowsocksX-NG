//
//  SynchronizedDisposeType.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 10/25/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

protocol SynchronizedDisposeType : class, Disposable, Lock {
    func _synchronized_dispose()
}

extension SynchronizedDisposeType {
    func synchronizedDispose() {
        self.lock(); defer { self.unlock() }
        self._synchronized_dispose()
    }
}
