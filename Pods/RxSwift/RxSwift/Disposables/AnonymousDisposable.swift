//
//  AnonymousDisposable.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 2/15/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

/// Represents an Action-based disposable.
///
/// When dispose method is called, disposal action will be dereferenced.
fileprivate final class AnonymousDisposable : DisposeBase, Cancelable {
    public typealias DisposeAction = () -> Void

    private var _isDisposed: AtomicInt = 0
    private var _disposeAction: DisposeAction?

    /// - returns: Was resource disposed.
    public var isDisposed: Bool {
        return _isDisposed == 1
    }

    /// Constructs a new disposable with the given action used for disposal.
    ///
    /// - parameter disposeAction: Disposal action which will be run upon calling `dispose`.
    fileprivate init(_ disposeAction: @escaping DisposeAction) {
        _disposeAction = disposeAction
        super.init()
    }
    
    // Non-deprecated version of the constructor, used by `Disposables.create(with:)`
    fileprivate init(disposeAction: @escaping DisposeAction) {
        _disposeAction = disposeAction
        super.init()
    }
    
    /// Calls the disposal action if and only if the current instance hasn't been disposed yet.
    ///
    /// After invoking disposal action, disposal action will be dereferenced.
    fileprivate func dispose() {
        if AtomicCompareAndSwap(0, 1, &_isDisposed) {
            assert(_isDisposed == 1)

            if let action = _disposeAction {
                _disposeAction = nil
                action()
            }
        }
    }
}

extension Disposables {
    
    /// Constructs a new disposable with the given action used for disposal.
    ///
    /// - parameter dispose: Disposal action which will be run upon calling `dispose`.
    public static func create(with dispose: @escaping () -> ()) -> Cancelable {
        return AnonymousDisposable(disposeAction: dispose)
    }
    
}
