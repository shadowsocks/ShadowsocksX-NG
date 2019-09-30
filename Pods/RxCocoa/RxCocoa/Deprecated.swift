//
//  Deprecated.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 3/19/17.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

import RxSwift
import Dispatch

extension ObservableType {

    /**
     Creates new subscription and sends elements to observer.

     In this form it's equivalent to `subscribe` method, but it communicates intent better, and enables
     writing more consistent binding code.

     - parameter observer: Observer that receives events.
     - returns: Disposable object that can be used to unsubscribe the observer.
     */
    @available(*, deprecated, renamed: "bind(to:)")
    public func bindTo<O: ObserverType>(_ observer: O) -> Disposable where O.E == E {
        return self.subscribe(observer)
    }

    /**
     Creates new subscription and sends elements to observer.

     In this form it's equivalent to `subscribe` method, but it communicates intent better, and enables
     writing more consistent binding code.

     - parameter observer: Observer that receives events.
     - returns: Disposable object that can be used to unsubscribe the observer.
     */
    @available(*, deprecated, renamed: "bind(to:)")
    public func bindTo<O: ObserverType>(_ observer: O) -> Disposable where O.E == E? {
        return self.map { $0 }.subscribe(observer)
    }

    /**
     Creates new subscription and sends elements to variable.

     In case error occurs in debug mode, `fatalError` will be raised.
     In case error occurs in release mode, `error` will be logged.

     - parameter variable: Target variable for sequence elements.
     - returns: Disposable object that can be used to unsubscribe the observer.
     */
    @available(*, deprecated, renamed: "bind(to:)")
    public func bindTo(_ variable: Variable<E>) -> Disposable {
        return self.subscribe { e in
            switch e {
            case let .next(element):
                variable.value = element
            case let .error(error):
                let error = "Binding error to variable: \(error)"
                #if DEBUG
                    rxFatalError(error)
                #else
                    print(error)
                #endif
            case .completed:
                break
            }
        }
    }

    /**
     Creates new subscription and sends elements to variable.

     In case error occurs in debug mode, `fatalError` will be raised.
     In case error occurs in release mode, `error` will be logged.

     - parameter variable: Target variable for sequence elements.
     - returns: Disposable object that can be used to unsubscribe the observer.
     */
    @available(*, deprecated, renamed: "bind(to:)")
    public func bindTo(_ variable: Variable<E?>) -> Disposable {
        return self.map { $0 as E? }.bindTo(variable)
    }

    /**
     Subscribes to observable sequence using custom binder function.

     - parameter binder: Function used to bind elements from `self`.
     - returns: Object representing subscription.
     */
    @available(*, deprecated, renamed: "bind(to:)")
    public func bindTo<R>(_ binder: (Self) -> R) -> R {
        return binder(self)
    }

    /**
     Subscribes to observable sequence using custom binder function and final parameter passed to binder function
     after `self` is passed.

     public func bindTo<R1, R2>(binder: Self -> R1 -> R2, curriedArgument: R1) -> R2 {
     return binder(self)(curriedArgument)
     }

     - parameter binder: Function used to bind elements from `self`.
     - parameter curriedArgument: Final argument passed to `binder` to finish binding process.
     - returns: Object representing subscription.
     */
    @available(*, deprecated, renamed: "bind(to:)")
    public func bindTo<R1, R2>(_ binder: (Self) -> (R1) -> R2, curriedArgument: R1) -> R2 {
        return binder(self)(curriedArgument)
    }


    /**
     Subscribes an element handler to an observable sequence.

     In case error occurs in debug mode, `fatalError` will be raised.
     In case error occurs in release mode, `error` will be logged.

     - parameter onNext: Action to invoke for each element in the observable sequence.
     - returns: Subscription object used to unsubscribe from the observable sequence.
     */
    @available(*, deprecated, renamed: "bind(onNext:)")
    public func bindNext(_ onNext: @escaping (E) -> Void) -> Disposable {
        return self.subscribe(onNext: onNext, onError: { error in
            let error = "Binding error: \(error)"
            #if DEBUG
                rxFatalError(error)
            #else
                print(error)
            #endif
        })
    }
}

#if os(iOS) || os(tvOS)
    import UIKit

    extension NSTextStorage {
        @available(*, unavailable, message: "createRxDelegateProxy is now unavailable, check DelegateProxyFactory")
        public func createRxDelegateProxy() -> RxTextStorageDelegateProxy {
            fatalError()
        }
    }

    extension UIScrollView {
        @available(*, unavailable, message: "createRxDelegateProxy is now unavailable, check DelegateProxyFactory")
        public func createRxDelegateProxy() -> RxScrollViewDelegateProxy {
            fatalError()
        }
    }

    extension UICollectionView {
        @available(*, unavailable, message: "createRxDataSourceProxy is now unavailable, check DelegateProxyFactory")
        public func createRxDataSourceProxy() -> RxCollectionViewDataSourceProxy {
            fatalError()
        }
    }

    extension UITableView {
        @available(*, unavailable, message: "createRxDataSourceProxy is now unavailable, check DelegateProxyFactory")
        public func createRxDataSourceProxy() -> RxTableViewDataSourceProxy {
            fatalError()
        }
    }

    extension UINavigationBar {
        @available(*, unavailable, message: "createRxDelegateProxy is now unavailable, check DelegateProxyFactory")
        public func createRxDelegateProxy() -> RxNavigationControllerDelegateProxy {
            fatalError()
        }
    }

    extension UINavigationController {
        @available(*, unavailable, message: "createRxDelegateProxy is now unavailable, check DelegateProxyFactory")
        public func createRxDelegateProxy() -> RxNavigationControllerDelegateProxy {
            fatalError()
        }
    }

    extension UITabBar {
        @available(*, unavailable, message: "createRxDelegateProxy is now unavailable, check DelegateProxyFactory")
        public func createRxDelegateProxy() -> RxTabBarDelegateProxy {
            fatalError()
        }
    }

    extension UITabBarController {
        @available(*, unavailable, message: "createRxDelegateProxy is now unavailable, check DelegateProxyFactory")
        public func createRxDelegateProxy() -> RxTabBarControllerDelegateProxy {
            fatalError()
        }
    }

    extension UISearchBar {
        @available(*, unavailable, message: "createRxDelegateProxy is now unavailable, check DelegateProxyFactory")
        public func createRxDelegateProxy() -> RxSearchBarDelegateProxy {
            fatalError()
        }
    }

#endif

#if os(iOS)
    extension UISearchController {
        @available(*, unavailable, message: "createRxDelegateProxy is now unavailable, check DelegateProxyFactory")
        public func createRxDelegateProxy() -> RxSearchControllerDelegateProxy {
            fatalError()
        }
    }

    extension UIPickerView {
        @available(*, unavailable, message: "createRxDelegateProxy is now unavailable, check DelegateProxyFactory")
        public func createRxDelegateProxy() -> RxPickerViewDelegateProxy {
            fatalError()
        }

        @available(*, unavailable, message: "createRxDataSourceProxy is now unavailable, check DelegateProxyFactory")
        public func createRxDataSourceProxy() -> RxPickerViewDataSourceProxy {
            fatalError()
        }
    }
    extension UIWebView {
        @available(*, unavailable, message: "createRxDelegateProxy is now unavailable, check DelegateProxyFactory")
        public func createRxDelegateProxy() -> RxWebViewDelegateProxy {
            fatalError()
        }
    }
#endif

#if os(macOS)
    import Cocoa

    extension NSTextField {
        @available(*, unavailable, message: "createRxDelegateProxy is now unavailable, check DelegateProxyFactory")
        public func createRxDelegateProxy() -> RxTextFieldDelegateProxy {
            fatalError()
        }
    }
#endif

/**
 This method can be used in unit tests to ensure that driver is using mock schedulers instead of
 main schedulers.

 **This shouldn't be used in normal release builds.**
 */
@available(*, deprecated, renamed: "SharingScheduler.mock(scheduler:action:)")
public func driveOnScheduler(_ scheduler: SchedulerType, action: () -> Void) {
    SharingScheduler.mock(scheduler: scheduler, action: action)
}

extension Variable {
    /// Converts `Variable` to `SharedSequence` unit.
    ///
    /// - returns: Observable sequence.
    @available(*, deprecated, renamed: "asDriver()")
    public func asSharedSequence<SharingStrategy: SharingStrategyProtocol>(strategy: SharingStrategy.Type = SharingStrategy.self) -> SharedSequence<SharingStrategy, E> {
        let source = self.asObservable()
            .observeOn(SharingStrategy.scheduler)
        return SharedSequence(source)
    }
}

#if !os(Linux)

extension DelegateProxy {
    @available(*, unavailable, renamed: "assignedProxy(for:)")
    public static func assignedProxyFor(_ object: ParentObject) -> Delegate? {
        fatalError()
    }
    
    @available(*, unavailable, renamed: "currentDelegate(for:)")
    public static func currentDelegateFor(_ object: ParentObject) -> Delegate? {
        fatalError()
    }
}

#endif

/**
Observer that enforces interface binding rules:
 * can't bind errors (in debug builds binding of errors causes `fatalError` in release builds errors are being logged)
 * ensures binding is performed on main thread
 
`UIBindingObserver` doesn't retain target interface and in case owned interface element is released, element isn't bound.
 
 In case event binding is attempted from non main dispatch queue, event binding will be dispatched async to main dispatch
 queue.
*/
@available(*, deprecated, renamed: "Binder")
public final class UIBindingObserver<UIElementType, Value> : ObserverType where UIElementType: AnyObject {
    public typealias E = Value

    weak var UIElement: UIElementType?

    let binding: (UIElementType, Value) -> Void

    /// Initializes `ViewBindingObserver` using
    @available(*, deprecated, renamed: "UIBinder.init(_:scheduler:binding:)")
    public init(UIElement: UIElementType, binding: @escaping (UIElementType, Value) -> Void) {
        self.UIElement = UIElement
        self.binding = binding
    }

    /// Binds next element to owner view as described in `binding`.
    public func on(_ event: Event<Value>) {
        if !DispatchQueue.isMain {
            DispatchQueue.main.async {
                self.on(event)
            }
            return
        }

        switch event {
        case .next(let element):
            if let view = self.UIElement {
                self.binding(view, element)
            }
        case .error(let error):
            bindingError(error)
        case .completed:
            break
        }
    }

    /// Erases type of observer.
    ///
    /// - returns: type erased observer.
    public func asObserver() -> AnyObserver<Value> {
        return AnyObserver(eventHandler: self.on)
    }
}


#if os(iOS)
    extension Reactive where Base: UIRefreshControl {

        /// Bindable sink for `beginRefreshing()`, `endRefreshing()` methods.
        @available(*, deprecated, renamed: "isRefreshing")
        public var refreshing: Binder<Bool> {
            return self.isRefreshing
        }
    }
#endif

#if os(iOS) || os(tvOS)
extension Reactive where Base: UIImageView {

    /// Bindable sink for `image` property.
    /// - parameter transitionType: Optional transition type while setting the image (kCATransitionFade, kCATransitionMoveIn, ...)
    @available(*, deprecated, renamed: "image")
    public func image(transitionType: String? = nil) -> Binder<UIImage?> {
        return Binder(base) { imageView, image in
            if let transitionType = transitionType {
                if image != nil {
                    let transition = CATransition()
                    transition.duration = 0.25
                    #if swift(>=4.2)
                        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        transition.type = CATransitionType(rawValue: transitionType)
                    #else
                        transition.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
                        transition.type = transitionType
                    #endif
                    imageView.layer.add(transition, forKey: kCATransition)
                }
            }
            else {
                imageView.layer.removeAllAnimations()
            }
            imageView.image = image
        }
    }
}
    
extension Reactive where Base: UISegmentedControl {
    @available(*, deprecated, renamed: "enabledForSegment(at:)")
    public func enabled(forSegmentAt segmentAt: Int) -> Binder<Bool> {
        return enabledForSegment(at: segmentAt)
    }
}
#endif

#if os(macOS)

    extension Reactive where Base: NSImageView {

        /// Bindable sink for `image` property.
        ///
        /// - parameter transitionType: Optional transition type while setting the image (kCATransitionFade, kCATransitionMoveIn, ...)
        @available(*, deprecated, renamed: "image")
        public func image(transitionType: String? = nil) -> Binder<NSImage?> {
            return Binder(self.base) { control, value in
                if let transitionType = transitionType {
                    if value != nil {
                        let transition = CATransition()
                        transition.duration = 0.25
#if swift(>=4.2)
                        transition.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
                        transition.type = CATransitionType(rawValue: transitionType)
#else
                        transition.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
                        transition.type = transitionType
#endif
                        control.layer?.add(transition, forKey: kCATransition)
                    }
                }
                else {
                    control.layer?.removeAllAnimations()
                }
                control.image = value
            }
        }
    }
#endif

import RxSwift

extension Variable {
    /// Converts `Variable` to `Driver` trait.
    ///
    /// - returns: Driving observable sequence.
    public func asDriver() -> Driver<E> {
        let source = self.asObservable()
            .observeOn(DriverSharingStrategy.scheduler)
        return Driver(source)
    }
}


private let errorMessage = "`drive*` family of methods can be only called from `MainThread`.\n" +
"This is required to ensure that the last replayed `Driver` element is delivered on `MainThread`.\n"

extension SharedSequenceConvertibleType where SharingStrategy == DriverSharingStrategy {
    /**
     Creates new subscription and sends elements to variable.
     This method can be only called from `MainThread`.

     - parameter variable: Target variable for sequence elements.
     - returns: Disposable object that can be used to unsubscribe the observer from the variable.
     */
    public func drive(_ variable: Variable<E>) -> Disposable {
        MainScheduler.ensureRunningOnMainThread(errorMessage: errorMessage)
        return self.drive(onNext: { e in
            variable.value = e
        })
    }

    /**
     Creates new subscription and sends elements to variable.
     This method can be only called from `MainThread`.

     - parameter variable: Target variable for sequence elements.
     - returns: Disposable object that can be used to unsubscribe the observer from the variable.
     */
    public func drive(_ variable: Variable<E?>) -> Disposable {
        MainScheduler.ensureRunningOnMainThread(errorMessage: errorMessage)
        return self.drive(onNext: { e in
            variable.value = e
        })
    }
}

extension ObservableType {
    /**
     Creates new subscription and sends elements to variable.

     In case error occurs in debug mode, `fatalError` will be raised.
     In case error occurs in release mode, `error` will be logged.

     - parameter to: Target variable for sequence elements.
     - returns: Disposable object that can be used to unsubscribe the observer.
     */
    public func bind(to variable: Variable<E>) -> Disposable {
        return self.subscribe { e in
            switch e {
            case let .next(element):
                variable.value = element
            case let .error(error):
                let error = "Binding error to variable: \(error)"
                #if DEBUG
                    rxFatalError(error)
                #else
                    print(error)
                #endif
            case .completed:
                break
            }
        }
    }

    /**
     Creates new subscription and sends elements to variable.

     In case error occurs in debug mode, `fatalError` will be raised.
     In case error occurs in release mode, `error` will be logged.

     - parameter to: Target variable for sequence elements.
     - returns: Disposable object that can be used to unsubscribe the observer.
     */
    public func bind(to variable: Variable<E?>) -> Disposable {
        return self.map { $0 as E? }.bind(to: variable)
    }
}


