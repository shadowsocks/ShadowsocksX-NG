//
//  BinaryDisposable.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 6/12/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

/// Represents two disposable resources that are disposed together.
private final class BinaryDisposable : DisposeBase, Cancelable {

    private let disposed = AtomicInt(0)

    // state
    private var disposable1: Disposable?
    private var disposable2: Disposable?

    /// - returns: Was resource disposed.
    var isDisposed: Bool {
        isFlagSet(self.disposed, 1)
    }

    /// Constructs new binary disposable from two disposables.
    ///
    /// - parameter disposable1: First disposable
    /// - parameter disposable2: Second disposable
    init(_ disposable1: Disposable, _ disposable2: Disposable) {
        self.disposable1 = disposable1
        self.disposable2 = disposable2
        super.init()
    }

    /// Calls the disposal action if and only if the current instance hasn't been disposed yet.
    ///
    /// After invoking disposal action, disposal action will be dereferenced.
    func dispose() {
        if fetchOr(self.disposed, 1) == 0 {
            self.disposable1?.dispose()
            self.disposable2?.dispose()
            self.disposable1 = nil
            self.disposable2 = nil
        }
    }
}

extension Disposables {

    /// Creates a disposable with the given disposables.
    public static func create(_ disposable1: Disposable, _ disposable2: Disposable) -> Cancelable {
        BinaryDisposable(disposable1, disposable2)
    }

}
