//
//  SingleAssignmentDisposable.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 2/15/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

/**
Represents a disposable resource which only allows a single assignment of its underlying disposable resource.

If an underlying disposable resource has already been set, future attempts to set the underlying disposable resource will throw an exception.
*/
public class SingleAssignmentDisposable : DisposeBase, Disposable, Cancelable {
#if os(Linux)
    fileprivate let _lock = SpinLock()
#endif

    fileprivate enum DisposeState: UInt32 {
        case disposed = 1
        case disposableSet = 2
    }

    // Jeej, swift API consistency rules
    fileprivate enum DisposeStateInt32: Int32 {
        case disposed = 1
        case disposableSet = 2
    }

    // state
    private var _state: UInt32 = 0
    private var _disposable = nil as Disposable?

    /// - returns: A value that indicates whether the object is disposed.
    public var isDisposed: Bool {
        return (_state & DisposeState.disposed.rawValue) != 0
    }

    /// Initializes a new instance of the `SingleAssignmentDisposable`.
    public override init() {
        super.init()
    }

    /// Gets or sets the underlying disposable. After disposal, the result of getting this property is undefined.
    ///
    /// **Throws exception if the `SingleAssignmentDisposable` has already been assigned to.**
    public func setDisposable(_ disposable: Disposable) {
        _disposable = disposable

        #if os(Linux)
        _lock.lock()
        let previousState = Int32(_state)
        _state = _state | DisposeState.disposableSet.rawValue
        // We know about `defer { _lock.unlock() }`, but this resolves Swift compiler bug. Using `defer` here causes anomaly.
        _lock.unlock()
        #else
        let previousState = OSAtomicOr32OrigBarrier(DisposeState.disposableSet.rawValue, &_state)
        #endif
        
        if (previousState & DisposeStateInt32.disposableSet.rawValue) != 0 {
            rxFatalError("oldState.disposable != nil")
        }

        if (previousState & DisposeStateInt32.disposed.rawValue) != 0 {
            disposable.dispose()
            _disposable = nil
        }
    }

    /// Disposes the underlying disposable.
    public func dispose() {
        #if os(Linux)
        _lock.lock()
        let previousState = Int32(_state)
        _state = _state | DisposeState.disposed.rawValue
        // We know about `defer { _lock.unlock() }`, but this resolves Swift compiler bug. Using `defer` here causes anomaly.
        _lock.unlock()
        #else
        let previousState = OSAtomicOr32OrigBarrier(DisposeState.disposed.rawValue, &_state)
        #endif

        if (previousState & DisposeStateInt32.disposed.rawValue) != 0 {
            return
        }

        if (previousState & DisposeStateInt32.disposableSet.rawValue) != 0 {
            guard let disposable = _disposable else {
                rxFatalError("Disposable not set")
            }
            disposable.dispose()
            _disposable = nil
        }
    }

}
