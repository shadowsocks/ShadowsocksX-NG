//
//  RxCocoaObjCRuntimeError+Extensions.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 10/9/16.
//  Copyright © 2016 Krunoslav Zaher. All rights reserved.
//

#if !RX_NO_MODULE
    #if SWIFT_PACKAGE && !DISABLE_SWIZZLING && !os(Linux)
        import RxCocoaRuntime
    #endif
#endif

#if !DISABLE_SWIZZLING && !os(Linux)
    /// RxCocoa ObjC runtime interception mechanism.
    public enum RxCocoaInterceptionMechanism {
        /// Unknown message interception mechanism.
        case unknown
        /// Key value observing interception mechanism.
        case kvo
    }

    /// RxCocoa ObjC runtime modification errors.
    public enum RxCocoaObjCRuntimeError
        : Swift.Error
        , CustomDebugStringConvertible {
        /// Unknown error has occurred.
        case unknown(target: AnyObject)

        /**
        If the object is reporting a different class then it's real class, that means that there is probably
        already some interception mechanism in place or something weird is happening.

        The most common case when this would happen is when using a combination of KVO (`observe`) and `sentMessage`.

        This error is easily resolved by just using `sentMessage` observing before `observe`.

        The reason why the other way around could create issues is because KVO will unregister it's interceptor
        class and restore original class. Unfortunately that will happen no matter was there another interceptor
        subclass registered in hierarchy or not.

        Failure scenario:
        * KVO sets class to be `__KVO__OriginalClass` (subclass of `OriginalClass`)
        * `sentMessage` sets object class to be `_RX_namespace___KVO__OriginalClass` (subclass of `__KVO__OriginalClass`)
        * then unobserving with KVO will restore class to be `OriginalClass` -> failure point (possibly a bug in KVO)

        The reason why changing order of observing works is because any interception method on unregistration 
        should return object's original real class (if that doesn't happen then it's really easy to argue that's a bug
        in that interception mechanism).

        This library won't remove registered interceptor even if there aren't any observers left because
        it's highly unlikely it would have any benefit in real world use cases, and it's even more
        dangerous.
        */
        case objectMessagesAlreadyBeingIntercepted(target: AnyObject, interceptionMechanism: RxCocoaInterceptionMechanism)

        /// Trying to observe messages for selector that isn't implemented.
        case selectorNotImplemented(target: AnyObject)

        /// Core Foundation classes are usually toll free bridged. Those classes crash the program in case
        /// `object_setClass` is performed on them.
        ///
        /// There is a possibility to just swizzle methods on original object, but since those won't be usual use
        /// cases for this library, then an error will just be reported for now.
        case cantInterceptCoreFoundationTollFreeBridgedObjects(target: AnyObject)

        /// Two libraries have simultaneously tried to modify ObjC runtime and that was detected. This can only
        /// happen in scenarios where multiple interception libraries are used.
        ///
        /// To synchronize other libraries intercepting messages for an object, use `synchronized` on target object and
        /// it's meta-class.
        case threadingCollisionWithOtherInterceptionMechanism(target: AnyObject)

        /// For some reason saving original method implementation under RX namespace failed.
        case savingOriginalForwardingMethodFailed(target: AnyObject)

        /// Intercepting a sent message by replacing a method implementation with `_objc_msgForward` failed for some reason.
        case replacingMethodWithForwardingImplementation(target: AnyObject)

        /// Attempt to intercept one of the performance sensitive methods:
        ///    * class
        ///    * respondsToSelector:
        ///    * methodSignatureForSelector:
        ///    * forwardingTargetForSelector:
        case observingPerformanceSensitiveMessages(target: AnyObject)

        /// Message implementation has unsupported return type (for example large struct). The reason why this is a error
        /// is because in some cases intercepting sent messages requires replacing implementation with `_objc_msgForward_stret`
        /// instead of `_objc_msgForward`.
        ///
        /// The unsupported cases should be fairly uncommon.
        case observingMessagesWithUnsupportedReturnType(target: AnyObject)
    }

    extension RxCocoaObjCRuntimeError {
        /// A textual representation of `self`, suitable for debugging.
        public var debugDescription: String {
            switch self {
            case let .unknown(target):
                return "Unknown error occurred.\nTarget: `\(target)`"
            case let .objectMessagesAlreadyBeingIntercepted(target, interceptionMechanism):
                let interceptionMechanismDescription = interceptionMechanism == .kvo ? "KVO" : "other interception mechanism"
                return "Collision between RxCocoa interception mechanism and \(interceptionMechanismDescription)."
                    + " To resolve this conflict please use this interception mechanism first.\nTarget: \(target)"
            case let .selectorNotImplemented(target):
                return "Trying to observe messages for selector that isn't implemented.\nTarget: \(target)"
            case let .cantInterceptCoreFoundationTollFreeBridgedObjects(target):
                return "Interception of messages sent to Core Foundation isn't supported.\nTarget: \(target)"
            case let .threadingCollisionWithOtherInterceptionMechanism(target):
                return "Detected a conflict while modifying ObjC runtime.\nTarget: \(target)"
            case let .savingOriginalForwardingMethodFailed(target):
                return "Saving original method implementation failed.\nTarget: \(target)"
            case let .replacingMethodWithForwardingImplementation(target):
                return "Intercepting a sent message by replacing a method implementation with `_objc_msgForward` failed for some reason.\nTarget: \(target)"
            case let .observingPerformanceSensitiveMessages(target):
                return "Attempt to intercept one of the performance sensitive methods. \nTarget: \(target)"
            case let .observingMessagesWithUnsupportedReturnType(target):
                return "Attempt to intercept a method with unsupported return type. \nTarget: \(target)"
            }
        }
    }
    
    // MARK: Conversions `NSError` > `RxCocoaObjCRuntimeError`

    extension Error {
        func rxCocoaErrorForTarget(_ target: AnyObject) -> RxCocoaObjCRuntimeError {
            let error = self as NSError
            
            if error.domain == RXObjCRuntimeErrorDomain {
                let errorCode = RXObjCRuntimeError(rawValue: error.code) ?? .unknown
                
                switch errorCode {
                case .unknown:
                    return .unknown(target: target)
                case .objectMessagesAlreadyBeingIntercepted:
                    let isKVO = (error.userInfo[RXObjCRuntimeErrorIsKVOKey] as? NSNumber)?.boolValue ?? false
                    return .objectMessagesAlreadyBeingIntercepted(target: target, interceptionMechanism: isKVO ? .kvo : .unknown)
                case .selectorNotImplemented:
                    return .selectorNotImplemented(target: target)
                case .cantInterceptCoreFoundationTollFreeBridgedObjects:
                    return .cantInterceptCoreFoundationTollFreeBridgedObjects(target: target)
                case .threadingCollisionWithOtherInterceptionMechanism:
                    return .threadingCollisionWithOtherInterceptionMechanism(target: target)
                case .savingOriginalForwardingMethodFailed:
                    return .savingOriginalForwardingMethodFailed(target: target)
                case .replacingMethodWithForwardingImplementation:
                    return .replacingMethodWithForwardingImplementation(target: target)
                case .observingPerformanceSensitiveMessages:
                    return .observingPerformanceSensitiveMessages(target: target)
                case .observingMessagesWithUnsupportedReturnType:
                    return .observingMessagesWithUnsupportedReturnType(target: target)
                }
            }
            
            return RxCocoaObjCRuntimeError.unknown(target: target)
        }
    }

#endif

