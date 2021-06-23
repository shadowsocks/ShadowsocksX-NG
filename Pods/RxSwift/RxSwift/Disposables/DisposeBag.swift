//
//  DisposeBag.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/25/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension Disposable {
    /// Adds `self` to `bag`
    ///
    /// - parameter bag: `DisposeBag` to add `self` to.
    public func disposed(by bag: DisposeBag) {
        bag.insert(self)
    }
}

/**
Thread safe bag that disposes added disposables on `deinit`.

This returns ARC (RAII) like resource management to `RxSwift`.

In case contained disposables need to be disposed, just put a different dispose bag
or create a new one in its place.

    self.existingDisposeBag = DisposeBag()

In case explicit disposal is necessary, there is also `CompositeDisposable`.
*/
public final class DisposeBag: DisposeBase {
    
    private var lock = SpinLock()
    
    // state
    private var disposables = [Disposable]()
    private var isDisposed = false
    
    /// Constructs new empty dispose bag.
    public override init() {
        super.init()
    }

    /// Adds `disposable` to be disposed when dispose bag is being deinited.
    ///
    /// - parameter disposable: Disposable to add.
    public func insert(_ disposable: Disposable) {
        self._insert(disposable)?.dispose()
    }
    
    private func _insert(_ disposable: Disposable) -> Disposable? {
        self.lock.performLocked {
            if self.isDisposed {
                return disposable
            }

            self.disposables.append(disposable)

            return nil
        }
    }

    /// This is internal on purpose, take a look at `CompositeDisposable` instead.
    private func dispose() {
        let oldDisposables = self._dispose()

        for disposable in oldDisposables {
            disposable.dispose()
        }
    }

    private func _dispose() -> [Disposable] {
        self.lock.performLocked {
            let disposables = self.disposables
            
            self.disposables.removeAll(keepingCapacity: false)
            self.isDisposed = true
            
            return disposables
        }
    }
    
    deinit {
        self.dispose()
    }
}

extension DisposeBag {
    /// Convenience init allows a list of disposables to be gathered for disposal.
    public convenience init(disposing disposables: Disposable...) {
        self.init()
        self.disposables += disposables
    }

    /// Convenience init which utilizes a function builder to let you pass in a list of
    /// disposables to make a DisposeBag of.
    public convenience init(@DisposableBuilder builder: () -> [Disposable]) {
      self.init(disposing: builder())
    }

    /// Convenience init allows an array of disposables to be gathered for disposal.
    public convenience init(disposing disposables: [Disposable]) {
        self.init()
        self.disposables += disposables
    }

    /// Convenience function allows a list of disposables to be gathered for disposal.
    public func insert(_ disposables: Disposable...) {
        self.insert(disposables)
    }

    /// Convenience function allows a list of disposables to be gathered for disposal.
    public func insert(@DisposableBuilder builder: () -> [Disposable]) {
        self.insert(builder())
    }

    /// Convenience function allows an array of disposables to be gathered for disposal.
    public func insert(_ disposables: [Disposable]) {
        self.lock.performLocked {
            if self.isDisposed {
                disposables.forEach { $0.dispose() }
            } else {
                self.disposables += disposables
            }
        }
    }

    /// A function builder accepting a list of Disposables and returning them as an array.
    #if swift(>=5.4)
    @resultBuilder
    public struct DisposableBuilder {
      public static func buildBlock(_ disposables: Disposable...) -> [Disposable] {
        return disposables
      }
    }
    #else
    @_functionBuilder
    public struct DisposableBuilder {
      public static func buildBlock(_ disposables: Disposable...) -> [Disposable] {
        return disposables
      }
    }
    #endif
    
}
