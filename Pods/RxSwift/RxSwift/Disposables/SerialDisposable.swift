//
//  SerialDisposable.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/12/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

/// Represents a disposable resource whose underlying disposable resource can be replaced by another disposable resource, causing automatic disposal of the previous underlying disposable resource.
public final class SerialDisposable : DisposeBase, Cancelable {
    private var _lock = SpinLock()
    
    // state
    private var _current = nil as Disposable?
    private var _isDisposed = false
    
    /// - returns: Was resource disposed.
    public var isDisposed: Bool {
        return _isDisposed
    }
    
    /// Initializes a new instance of the `SerialDisposable`.
    override public init() {
        super.init()
    }
    
    /**
    Gets or sets the underlying disposable.
    
    Assigning this property disposes the previous disposable object.
    
    If the `SerialDisposable` has already been disposed, assignment to this property causes immediate disposal of the given disposable object.
    */
    public var disposable: Disposable {
        get {
            return _lock.calculateLocked {
                return _current ?? Disposables.create()
            }
        }
        set (newDisposable) {
            let disposable: Disposable? = _lock.calculateLocked {
                if _isDisposed {
                    return newDisposable
                }
                else {
                    let toDispose = _current
                    _current = newDisposable
                    return toDispose
                }
            }
            
            if let disposable = disposable {
                disposable.dispose()
            }
        }
    }
    
    /// Disposes the underlying disposable as well as all future replacements.
    public func dispose() {
        _dispose()?.dispose()
    }

    private func _dispose() -> Disposable? {
        _lock.lock(); defer { _lock.unlock() }
        if _isDisposed {
            return nil
        }
        else {
            _isDisposed = true
            let current = _current
            _current = nil
            return current
        }
    }
}
