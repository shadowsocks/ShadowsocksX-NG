//
//  BooleanDisposable.swift
//  RxSwift
//
//  Created by Junior B. on 10/29/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

/// Represents a disposable resource that can be checked for disposal status.
public final class BooleanDisposable : Disposable, Cancelable {

    internal static let BooleanDisposableTrue = BooleanDisposable(isDisposed: true)
    private var _isDisposed = false
    
    /// Initializes a new instance of the `BooleanDisposable` class
    public init() {
    }
    
    /// Initializes a new instance of the `BooleanDisposable` class with given value
    public init(isDisposed: Bool) {
        self._isDisposed = isDisposed
    }
    
    /// - returns: Was resource disposed.
    public var isDisposed: Bool {
        return _isDisposed
    }
    
    /// Sets the status to disposed, which can be observer through the `isDisposed` property.
    public func dispose() {
        _isDisposed = true
    }
}
