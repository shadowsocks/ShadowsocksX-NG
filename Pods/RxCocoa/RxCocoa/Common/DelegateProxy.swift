//
//  DelegateProxy.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 6/14/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if !os(Linux)

    import RxSwift
    #if SWIFT_PACKAGE && !os(Linux)
        import RxCocoaRuntime
    #endif

    /// Base class for `DelegateProxyType` protocol.
    ///
    /// This implementation is not thread safe and can be used only from one thread (Main thread).
    open class DelegateProxy<P: AnyObject, D>: _RXDelegateProxy {
        public typealias ParentObject = P
        public typealias Delegate = D

        private var _sentMessageForSelector = [Selector: MessageDispatcher]()
        private var _methodInvokedForSelector = [Selector: MessageDispatcher]()

        /// Parent object associated with delegate proxy.
        private weak var _parentObject: ParentObject?

        private let _currentDelegateFor: (ParentObject) -> AnyObject?
        private let _setCurrentDelegateTo: (AnyObject?, ParentObject) -> Void

        /// Initializes new instance.
        ///
        /// - parameter parentObject: Optional parent object that owns `DelegateProxy` as associated object.
        public init<Proxy: DelegateProxyType>(parentObject: ParentObject, delegateProxy: Proxy.Type)
            where Proxy: DelegateProxy<ParentObject, Delegate>, Proxy.ParentObject == ParentObject, Proxy.Delegate == Delegate {
            self._parentObject = parentObject
            self._currentDelegateFor = delegateProxy._currentDelegate
            self._setCurrentDelegateTo = delegateProxy._setCurrentDelegate

            MainScheduler.ensureRunningOnMainThread()
            #if TRACE_RESOURCES
                _ = Resources.incrementTotal()
            #endif
            super.init()
        }

        /**
         Returns observable sequence of invocations of delegate methods. Elements are sent *before method is invoked*.

         Only methods that have `void` return value can be observed using this method because
         those methods are used as a notification mechanism. It doesn't matter if they are optional
         or not. Observing is performed by installing a hidden associated `PublishSubject` that is
         used to dispatch messages to observers.

         Delegate methods that have non `void` return value can't be observed directly using this method
         because:
         * those methods are not intended to be used as a notification mechanism, but as a behavior customization mechanism
         * there is no sensible automatic way to determine a default return value

         In case observing of delegate methods that have return type is required, it can be done by
         manually installing a `PublishSubject` or `BehaviorSubject` and implementing delegate method.

         e.g.

             // delegate proxy part (RxScrollViewDelegateProxy)

             let internalSubject = PublishSubject<CGPoint>

             public func requiredDelegateMethod(scrollView: UIScrollView, arg1: CGPoint) -> Bool {
                 internalSubject.on(.next(arg1))
                 return self._forwardToDelegate?.requiredDelegateMethod?(scrollView, arg1: arg1) ?? defaultReturnValue
             }

         ....

             // reactive property implementation in a real class (`UIScrollView`)
             public var property: Observable<CGPoint> {
                 let proxy = RxScrollViewDelegateProxy.proxy(for: base)
                 return proxy.internalSubject.asObservable()
             }

         **In case calling this method prints "Delegate proxy is already implementing `\(selector)`,
         a more performant way of registering might exist.", that means that manual observing method
         is required analog to the example above because delegate method has already been implemented.**

         - parameter selector: Selector used to filter observed invocations of delegate methods.
         - returns: Observable sequence of arguments passed to `selector` method.
         */
        open func sentMessage(_ selector: Selector) -> Observable<[Any]> {
            MainScheduler.ensureRunningOnMainThread()

            let subject = self._sentMessageForSelector[selector]

            if let subject = subject {
                return subject.asObservable()
            }
            else {
                let subject = MessageDispatcher(selector: selector, delegateProxy: self)
                self._sentMessageForSelector[selector] = subject
                return subject.asObservable()
            }
        }

        /**
         Returns observable sequence of invoked delegate methods. Elements are sent *after method is invoked*.

         Only methods that have `void` return value can be observed using this method because
         those methods are used as a notification mechanism. It doesn't matter if they are optional
         or not. Observing is performed by installing a hidden associated `PublishSubject` that is
         used to dispatch messages to observers.

         Delegate methods that have non `void` return value can't be observed directly using this method
         because:
         * those methods are not intended to be used as a notification mechanism, but as a behavior customization mechanism
         * there is no sensible automatic way to determine a default return value

         In case observing of delegate methods that have return type is required, it can be done by
         manually installing a `PublishSubject` or `BehaviorSubject` and implementing delegate method.

         e.g.

             // delegate proxy part (RxScrollViewDelegateProxy)

             let internalSubject = PublishSubject<CGPoint>

             public func requiredDelegateMethod(scrollView: UIScrollView, arg1: CGPoint) -> Bool {
                 internalSubject.on(.next(arg1))
                 return self._forwardToDelegate?.requiredDelegateMethod?(scrollView, arg1: arg1) ?? defaultReturnValue
             }

         ....

             // reactive property implementation in a real class (`UIScrollView`)
             public var property: Observable<CGPoint> {
                 let proxy = RxScrollViewDelegateProxy.proxy(for: base)
                 return proxy.internalSubject.asObservable()
             }

         **In case calling this method prints "Delegate proxy is already implementing `\(selector)`,
         a more performant way of registering might exist.", that means that manual observing method
         is required analog to the example above because delegate method has already been implemented.**

         - parameter selector: Selector used to filter observed invocations of delegate methods.
         - returns: Observable sequence of arguments passed to `selector` method.
         */
        open func methodInvoked(_ selector: Selector) -> Observable<[Any]> {
            MainScheduler.ensureRunningOnMainThread()

            let subject = self._methodInvokedForSelector[selector]

            if let subject = subject {
                return subject.asObservable()
            }
            else {
                let subject = MessageDispatcher(selector: selector, delegateProxy: self)
                self._methodInvokedForSelector[selector] = subject
                return subject.asObservable()
            }
        }

        fileprivate func checkSelectorIsObservable(_ selector: Selector) {
            MainScheduler.ensureRunningOnMainThread()

            if self.hasWiredImplementation(for: selector) {
                print("⚠️ Delegate proxy is already implementing `\(selector)`, a more performant way of registering might exist.")
                return
            }

            if self.voidDelegateMethodsContain(selector) {
                return
            }

            // In case `_forwardToDelegate` is `nil`, it is assumed the check is being done prematurely.
            if !(self._forwardToDelegate?.responds(to: selector) ?? true) {
                print("⚠️ Using delegate proxy dynamic interception method but the target delegate object doesn't respond to the requested selector. " +
                    "In case pure Swift delegate proxy is being used please use manual observing method by using`PublishSubject`s. " +
                    " (selector: `\(selector)`, forwardToDelegate: `\(self._forwardToDelegate ?? self)`)")
            }
        }

        // proxy

        open override func _sentMessage(_ selector: Selector, withArguments arguments: [Any]) {
            self._sentMessageForSelector[selector]?.on(.next(arguments))
        }

        open override func _methodInvoked(_ selector: Selector, withArguments arguments: [Any]) {
            self._methodInvokedForSelector[selector]?.on(.next(arguments))
        }

        /// Returns reference of normal delegate that receives all forwarded messages
        /// through `self`.
        ///
        /// - returns: Value of reference if set or nil.
        open func forwardToDelegate() -> Delegate? {
            return castOptionalOrFatalError(self._forwardToDelegate)
        }

        /// Sets reference of normal delegate that receives all forwarded messages
        /// through `self`.
        ///
        /// - parameter forwardToDelegate: Reference of delegate that receives all messages through `self`.
        /// - parameter retainDelegate: Should `self` retain `forwardToDelegate`.
        open func setForwardToDelegate(_ delegate: Delegate?, retainDelegate: Bool) {
            #if DEBUG // 4.0 all configurations
                MainScheduler.ensureRunningOnMainThread()
            #endif
            self._setForwardToDelegate(delegate, retainDelegate: retainDelegate)

            let sentSelectors: [Selector] = self._sentMessageForSelector.values.filter { $0.hasObservers }.map { $0.selector }
            let invokedSelectors: [Selector] = self._methodInvokedForSelector.values.filter { $0.hasObservers }.map { $0.selector }
            let allUsedSelectors = sentSelectors + invokedSelectors

            for selector in Set(allUsedSelectors) {
                self.checkSelectorIsObservable(selector)
            }

            self.reset()
        }

        private func hasObservers(selector: Selector) -> Bool {
            return (self._sentMessageForSelector[selector]?.hasObservers ?? false)
                || (self._methodInvokedForSelector[selector]?.hasObservers ?? false)
        }

        override open func responds(to aSelector: Selector!) -> Bool {
            return super.responds(to: aSelector)
                || (self._forwardToDelegate?.responds(to: aSelector) ?? false)
                || (self.voidDelegateMethodsContain(aSelector) && self.hasObservers(selector: aSelector))
        }

        fileprivate func reset() {
            guard let parentObject = self._parentObject else { return }

            let maybeCurrentDelegate = self._currentDelegateFor(parentObject)

            if maybeCurrentDelegate === self {
                self._setCurrentDelegateTo(nil, parentObject)
                self._setCurrentDelegateTo(castOrFatalError(self), parentObject)
            }
        }

        deinit {
            for v in self._sentMessageForSelector.values {
                v.on(.completed)
            }
            for v in self._methodInvokedForSelector.values {
                v.on(.completed)
            }
            #if TRACE_RESOURCES
                _ = Resources.decrementTotal()
            #endif
        }
    

    }

    private let mainScheduler = MainScheduler()

    private final class MessageDispatcher {
        private let dispatcher: PublishSubject<[Any]>
        private let result: Observable<[Any]>

        fileprivate let selector: Selector

        init<P, D>(selector: Selector, delegateProxy _delegateProxy: DelegateProxy<P, D>) {
            weak var weakDelegateProxy = _delegateProxy

            let dispatcher = PublishSubject<[Any]>()
            self.dispatcher = dispatcher
            self.selector = selector

            self.result = dispatcher
                .do(onSubscribed: { weakDelegateProxy?.checkSelectorIsObservable(selector); weakDelegateProxy?.reset() }, onDispose: { weakDelegateProxy?.reset() })
                .share()
                .subscribeOn(mainScheduler)
        }

        var on: (Event<[Any]>) -> Void {
            return self.dispatcher.on
        }

        var hasObservers: Bool {
            return self.dispatcher.hasObservers
        }

        func asObservable() -> Observable<[Any]> {
            return self.result
        }
    }
    
#endif
