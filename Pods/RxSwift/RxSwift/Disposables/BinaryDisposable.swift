//
//  BinaryDisposable.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 6/12/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

/// Represents two disposable resources that are disposed together.
private final class BinaryDisposable : DisposeBase, Cancelable {

    private var _isDisposed: AtomicInt = 0

    // state
    private var _disposable1: Disposable?
    private var _disposable2: Disposable?

    /// - returns: Was resource disposed.
    var isDisposed: Bool {
        return _isDisposed > 0
    }

    /// Constructs new binary disposable from two disposables.
    ///
    /// - parameter disposable1: First disposable
    /// - parameter disposable2: Second disposable
    init(_ disposable1: Disposable, _ disposable2: Disposable) {
        _disposable1 = disposable1
        _disposable2 = disposable2
        super.init()
    }

    /// Calls the disposal action if and only if the current instance hasn't been disposed yet.
    ///
    /// After invoking disposal action, disposal action will be dereferenced.
    func dispose() {
        if AtomicCompareAndSwap(0, 1, &_isDisposed) {
            _disposable1?.dispose()
            _disposable2?.dispose()
            _disposable1 = nil
            _disposable2 = nil
        }
    }
}

extension Disposables {
    
    /// Creates a disposable with the given disposables.
    public static func create(_ disposable1: Disposable, _ disposable2: Disposable) -> Cancelable {
        return BinaryDisposable(disposable1, disposable2)
    }
    
}
