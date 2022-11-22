//
//  SingleAssignmentDisposable.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 2/15/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

/**
Represents a disposable resource which only allows a single assignment of its underlying disposable resource.

If an underlying disposable resource has already been set, future attempts to set the underlying disposable resource will throw an exception.
*/
public final class SingleAssignmentDisposable : DisposeBase, Cancelable {

    private struct DisposeState: OptionSet {
        let rawValue: Int32
        
        static let disposed = DisposeState(rawValue: 1 << 0)
        static let disposableSet = DisposeState(rawValue: 1 << 1)
    }

    // state
    private let state = AtomicInt(0)
    private var disposable = nil as Disposable?

    /// - returns: A value that indicates whether the object is disposed.
    public var isDisposed: Bool {
        isFlagSet(self.state, DisposeState.disposed.rawValue)
    }

    /// Initializes a new instance of the `SingleAssignmentDisposable`.
    public override init() {
        super.init()
    }

    /// Gets or sets the underlying disposable. After disposal, the result of getting this property is undefined.
    ///
    /// **Throws exception if the `SingleAssignmentDisposable` has already been assigned to.**
    public func setDisposable(_ disposable: Disposable) {
        self.disposable = disposable

        let previousState = fetchOr(self.state, DisposeState.disposableSet.rawValue)

        if (previousState & DisposeState.disposableSet.rawValue) != 0 {
            rxFatalError("oldState.disposable != nil")
        }

        if (previousState & DisposeState.disposed.rawValue) != 0 {
            disposable.dispose()
            self.disposable = nil
        }
    }

    /// Disposes the underlying disposable.
    public func dispose() {
        let previousState = fetchOr(self.state, DisposeState.disposed.rawValue)

        if (previousState & DisposeState.disposed.rawValue) != 0 {
            return
        }

        if (previousState & DisposeState.disposableSet.rawValue) != 0 {
            guard let disposable = self.disposable else {
                rxFatalError("Disposable not set")
            }
            disposable.dispose()
            self.disposable = nil
        }
    }

}
