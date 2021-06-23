//
//  ScheduledDisposable.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 6/13/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

private let disposeScheduledDisposable: (ScheduledDisposable) -> Disposable = { sd in
    sd.disposeInner()
    return Disposables.create()
}

/// Represents a disposable resource whose disposal invocation will be scheduled on the specified scheduler.
public final class ScheduledDisposable : Cancelable {
    public let scheduler: ImmediateSchedulerType

    private let disposed = AtomicInt(0)

    // state
    private var disposable: Disposable?

    /// - returns: Was resource disposed.
    public var isDisposed: Bool {
        isFlagSet(self.disposed, 1)
    }

    /**
    Initializes a new instance of the `ScheduledDisposable` that uses a `scheduler` on which to dispose the `disposable`.

    - parameter scheduler: Scheduler where the disposable resource will be disposed on.
    - parameter disposable: Disposable resource to dispose on the given scheduler.
    */
    public init(scheduler: ImmediateSchedulerType, disposable: Disposable) {
        self.scheduler = scheduler
        self.disposable = disposable
    }

    /// Disposes the wrapped disposable on the provided scheduler.
    public func dispose() {
        _ = self.scheduler.schedule(self, action: disposeScheduledDisposable)
    }

    func disposeInner() {
        if fetchOr(self.disposed, 1) == 0 {
            self.disposable!.dispose()
            self.disposable = nil
        }
    }
}
