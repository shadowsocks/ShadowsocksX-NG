//
//  ObservableType+Extensions.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 2/21/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if DEBUG
    import Foundation
#endif

extension ObservableType {
    /**
     Subscribes an event handler to an observable sequence.
     
     - parameter on: Action to invoke for each event in the observable sequence.
     - returns: Subscription object used to unsubscribe from the observable sequence.
     */
    public func subscribe(_ on: @escaping (Event<E>) -> Void)
        -> Disposable {
            let observer = AnonymousObserver { e in
                on(e)
            }
            return self.asObservable().subscribe(observer)
    }
    
    
    /**
     Subscribes an element handler, an error handler, a completion handler and disposed handler to an observable sequence.
     
     - parameter onNext: Action to invoke for each element in the observable sequence.
     - parameter onError: Action to invoke upon errored termination of the observable sequence.
     - parameter onCompleted: Action to invoke upon graceful termination of the observable sequence.
     - parameter onDisposed: Action to invoke upon any type of termination of sequence (if the sequence has
     gracefully completed, errored, or if the generation is canceled by disposing subscription).
     - returns: Subscription object used to unsubscribe from the observable sequence.
     */
    public func subscribe(onNext: ((E) -> Void)? = nil, onError: ((Swift.Error) -> Void)? = nil, onCompleted: (() -> Void)? = nil, onDisposed: (() -> Void)? = nil)
        -> Disposable {
            #if DEBUG
                let disposable: Disposable
                
                if let disposed = onDisposed {
                    disposable = Disposables.create(with: disposed)
                }
                else {
                    disposable = Disposables.create()
                }
                
                let synchronizationTracker = SynchronizationTracker()

                let callStack = Hooks.recordCallStackOnError ? Thread.callStackSymbols : []

                let observer = AnonymousObserver<E> { event in
                    
                    synchronizationTracker.register(synchronizationErrorMessage: .default)
                    defer { synchronizationTracker.unregister() }
                    
                    switch event {
                    case .next(let value):
                        onNext?(value)
                    case .error(let error):
                        if let onError = onError {
                            onError(error)
                        }
                        else {
                            Hooks.defaultErrorHandler(callStack, error)
                        }
                        disposable.dispose()
                    case .completed:
                        onCompleted?()
                        disposable.dispose()
                    }
                }
                return Disposables.create(
                    self.asObservable().subscribe(observer),
                    disposable
                )
            #else
                let disposable: Disposable
                
                if let disposed = onDisposed {
                    disposable = Disposables.create(with: disposed)
                }
                else {
                    disposable = Disposables.create()
                }
                
                let observer = AnonymousObserver<E> { event in
                    switch event {
                    case .next(let value):
                        onNext?(value)
                    case .error(let error):
                        if let onError = onError {
                            onError(error)
                        }
                        else {
                            Hooks.defaultErrorHandler([], error)
                        }
                        disposable.dispose()
                    case .completed:
                        onCompleted?()
                        disposable.dispose()
                    }
                }
                return Disposables.create(
                    self.asObservable().subscribe(observer),
                    disposable
                )
            #endif
            
    }
}

import class Foundation.NSRecursiveLock

extension Hooks {
    public typealias DefaultErrorHandler = (_ subscriptionCallStack: [String], _ error: Error) -> ()

    fileprivate static let _lock = RecursiveLock()
    fileprivate static var _defaultErrorHandler: DefaultErrorHandler = { subscriptionCallStack, error in
        #if DEBUG
            let serializedCallStack = subscriptionCallStack.joined(separator: "\n")
            print("Unhandled error happened: \(error)\n subscription called from:\n\(serializedCallStack)")
        #endif
    }

    /// Error handler called in case onError handler wasn't provided.
    public static var defaultErrorHandler: DefaultErrorHandler {
        get {
            _lock.lock(); defer { _lock.unlock() }
            return _defaultErrorHandler
        }
        set {
            _lock.lock(); defer { _lock.unlock() }
            _defaultErrorHandler = newValue
        }
    }
}

