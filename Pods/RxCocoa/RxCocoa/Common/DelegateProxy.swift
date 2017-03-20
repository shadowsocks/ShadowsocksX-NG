//
//  DelegateProxy.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 6/14/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if !os(Linux)

#if !RX_NO_MODULE
    import RxSwift
    #if SWIFT_PACKAGE && !os(Linux)
        import RxCocoaRuntime
    #endif
#endif

var delegateAssociatedTag: UnsafeRawPointer = UnsafeRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1))
var dataSourceAssociatedTag: UnsafeRawPointer = UnsafeRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1))

/// Base class for `DelegateProxyType` protocol.
///
/// This implementation is not thread safe and can be used only from one thread (Main thread).
open class DelegateProxy : _RXDelegateProxy {

    private var sentMessageForSelector = [Selector: MessageDispatcher]()
    private var methodInvokedForSelector = [Selector: MessageDispatcher]()

    /// Parent object associated with delegate proxy.
    weak private(set) var parentObject: AnyObject?
    
    /// Initializes new instance.
    ///
    /// - parameter parentObject: Optional parent object that owns `DelegateProxy` as associated object.
    public required init(parentObject: AnyObject) {
        self.parentObject = parentObject
        
        MainScheduler.ensureExecutingOnScheduler()
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
             let proxy = RxScrollViewDelegateProxy.proxyForObject(base)
             return proxy.internalSubject.asObservable()
         }

     **In case calling this method prints "Delegate proxy is already implementing `\(selector)`, 
     a more performant way of registering might exist.", that means that manual observing method 
     is required analog to the example above because delegate method has already been implemented.**

    - parameter selector: Selector used to filter observed invocations of delegate methods.
    - returns: Observable sequence of arguments passed to `selector` method.
    */
    open func sentMessage(_ selector: Selector) -> Observable<[Any]> {
        MainScheduler.ensureExecutingOnScheduler()
        checkSelectorIsObservable(selector)

        let subject = sentMessageForSelector[selector]
        
        if let subject = subject {
            return subject.asObservable()
        }
        else {
            let subject = MessageDispatcher(delegateProxy: self)
            sentMessageForSelector[selector] = subject
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
             let proxy = RxScrollViewDelegateProxy.proxyForObject(base)
             return proxy.internalSubject.asObservable()
         }

     **In case calling this method prints "Delegate proxy is already implementing `\(selector)`, 
     a more performant way of registering might exist.", that means that manual observing method 
     is required analog to the example above because delegate method has already been implemented.**

    - parameter selector: Selector used to filter observed invocations of delegate methods.
    - returns: Observable sequence of arguments passed to `selector` method.
     */
    open func methodInvoked(_ selector: Selector) -> Observable<[Any]> {
        MainScheduler.ensureExecutingOnScheduler()
        checkSelectorIsObservable(selector)

        let subject = methodInvokedForSelector[selector]

        if let subject = subject {
            return subject.asObservable()
        }
        else {
            let subject = MessageDispatcher(delegateProxy: self)
            methodInvokedForSelector[selector] = subject
            return subject.asObservable()
        }
    }

    private func checkSelectorIsObservable(_ selector: Selector) {
        MainScheduler.ensureExecutingOnScheduler()

        if hasWiredImplementation(for: selector) {
            print("Delegate proxy is already implementing `\(selector)`, a more performant way of registering might exist.")
            return
        }

        guard (self.forwardToDelegate()?.responds(to: selector) ?? false) || voidDelegateMethodsContain(selector) else {
            rxFatalError("This class doesn't respond to selector \(selector)")
        }
    }

    // proxy

    open override func _sentMessage(_ selector: Selector, withArguments arguments: [Any]) {
        sentMessageForSelector[selector]?.on(.next(arguments))
    }

    open override func _methodInvoked(_ selector: Selector, withArguments arguments: [Any]) {
        methodInvokedForSelector[selector]?.on(.next(arguments))
    }

    /// Returns tag used to identify associated object.
    ///
    /// - returns: Associated object tag.
    open class func delegateAssociatedObjectTag() -> UnsafeRawPointer {
        return delegateAssociatedTag
    }
    
    /// Initializes new instance of delegate proxy.
    ///
    /// - returns: Initialized instance of `self`.
    open class func createProxyForObject(_ object: AnyObject) -> AnyObject {
        return self.init(parentObject: object)
    }
    
    /// Returns assigned proxy for object.
    ///
    /// - parameter object: Object that can have assigned delegate proxy.
    /// - returns: Assigned delegate proxy or `nil` if no delegate proxy is assigned.
    open class func assignedProxyFor(_ object: AnyObject) -> AnyObject? {
        let maybeDelegate = objc_getAssociatedObject(object, self.delegateAssociatedObjectTag())
        return castOptionalOrFatalError(maybeDelegate.map { $0 as AnyObject })
    }
    
    /// Assigns proxy to object.
    ///
    /// - parameter object: Object that can have assigned delegate proxy.
    /// - parameter proxy: Delegate proxy object to assign to `object`.
    open class func assignProxy(_ proxy: AnyObject, toObject object: AnyObject) {
        precondition(proxy.isKind(of: self.classForCoder()))
       
        objc_setAssociatedObject(object, self.delegateAssociatedObjectTag(), proxy, .OBJC_ASSOCIATION_RETAIN)
    }
    
    /// Sets reference of normal delegate that receives all forwarded messages
    /// through `self`.
    ///
    /// - parameter forwardToDelegate: Reference of delegate that receives all messages through `self`.
    /// - parameter retainDelegate: Should `self` retain `forwardToDelegate`.
    open func setForwardToDelegate(_ delegate: AnyObject?, retainDelegate: Bool) {
        #if DEBUG // 4.0 all configurations
            MainScheduler.ensureExecutingOnScheduler()
        #endif
        self._setForward(toDelegate: delegate, retainDelegate: retainDelegate)
        self.reset()
    }
   
    /// Returns reference of normal delegate that receives all forwarded messages
    /// through `self`.
    ///
    /// - returns: Value of reference if set or nil.
    open func forwardToDelegate() -> AnyObject? {
        return self._forwardToDelegate
    }

    private func hasObservers(selector: Selector) -> Bool {
        return (sentMessageForSelector[selector]?.hasObservers ?? false)
            || (methodInvokedForSelector[selector]?.hasObservers ?? false)
    }
    
    override open func responds(to aSelector: Selector!) -> Bool {
        return super.responds(to: aSelector)
            || (self._forwardToDelegate?.responds(to: aSelector) ?? false)
            || (self.voidDelegateMethodsContain(aSelector) && self.hasObservers(selector: aSelector))
    }

    internal func reset() {
        guard let delegateProxySelf = self as? DelegateProxyType else {
            rxFatalErrorInDebug("\(self) doesn't implement delegate proxy type.")
            return
        }
        
        guard let parentObject = self.parentObject else { return }

        let selfType = type(of: delegateProxySelf)

        let maybeCurrentDelegate = selfType.currentDelegateFor(parentObject)

        if maybeCurrentDelegate === self {
            selfType.setCurrentDelegate(nil, toObject: parentObject)
            selfType.setCurrentDelegate(self, toObject: parentObject)
        }
    }

    deinit {
        for v in sentMessageForSelector.values {
            v.on(.completed)
        }
        for v in methodInvokedForSelector.values {
            v.on(.completed)
        }
#if TRACE_RESOURCES
        _ = Resources.decrementTotal()
#endif
    }
}

fileprivate let mainScheduler = MainScheduler()

fileprivate final class MessageDispatcher {
    private let dispatcher: PublishSubject<[Any]>
    private let result: Observable<[Any]>

    init(delegateProxy _delegateProxy: DelegateProxy) {
        weak var weakDelegateProxy = _delegateProxy

        let dispatcher = PublishSubject<[Any]>()
        self.dispatcher = dispatcher

        self.result = dispatcher
            .do(onSubscribed: { weakDelegateProxy?.reset() }, onDispose: { weakDelegateProxy?.reset() })
            .share()
            .subscribeOn(mainScheduler)
    }

    var on: (Event<[Any]>) -> () {
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
