//
//  RefCountDisposable.swift
//  RxSwift
//
//  Created by Junior B. on 10/29/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

/// Represents a disposable resource that only disposes its underlying disposable resource when all dependent disposable objects have been disposed.
public final class RefCountDisposable : DisposeBase, Cancelable {
    private var lock = SpinLock()
    private var disposable = nil as Disposable?
    private var primaryDisposed = false
    private var count = 0

    /// - returns: Was resource disposed.
    public var isDisposed: Bool {
        self.lock.performLocked { self.disposable == nil }
    }

    /// Initializes a new instance of the `RefCountDisposable`.
    public init(disposable: Disposable) {
        self.disposable = disposable
        super.init()
    }

    /**
     Holds a dependent disposable that when disposed decreases the refcount on the underlying disposable.

     When getter is called, a dependent disposable contributing to the reference count that manages the underlying disposable's lifetime is returned.
     */
    public func retain() -> Disposable {
        self.lock.performLocked {
            if self.disposable != nil {
                do {
                    _ = try incrementChecked(&self.count)
                } catch {
                    rxFatalError("RefCountDisposable increment failed")
                }

                return RefCountInnerDisposable(self)
            } else {
                return Disposables.create()
            }
        }
    }

    /// Disposes the underlying disposable only when all dependent disposables have been disposed.
    public func dispose() {
        let oldDisposable: Disposable? = self.lock.performLocked {
            if let oldDisposable = self.disposable, !self.primaryDisposed {
                self.primaryDisposed = true

                if self.count == 0 {
                    self.disposable = nil
                    return oldDisposable
                }
            }

            return nil
        }

        if let disposable = oldDisposable {
            disposable.dispose()
        }
    }

    fileprivate func release() {
        let oldDisposable: Disposable? = self.lock.performLocked {
            if let oldDisposable = self.disposable {
                do {
                    _ = try decrementChecked(&self.count)
                } catch {
                    rxFatalError("RefCountDisposable decrement on release failed")
                }

                guard self.count >= 0 else {
                    rxFatalError("RefCountDisposable counter is lower than 0")
                }

                if self.primaryDisposed && self.count == 0 {
                    self.disposable = nil
                    return oldDisposable
                }
            }

            return nil
        }

        if let disposable = oldDisposable {
            disposable.dispose()
        }
    }
}

internal final class RefCountInnerDisposable: DisposeBase, Disposable
{
    private let parent: RefCountDisposable
    private let isDisposed = AtomicInt(0)

    init(_ parent: RefCountDisposable) {
        self.parent = parent
        super.init()
    }

    internal func dispose()
    {
        if fetchOr(self.isDisposed, 1) == 0 {
            self.parent.release()
        }
    }
}
