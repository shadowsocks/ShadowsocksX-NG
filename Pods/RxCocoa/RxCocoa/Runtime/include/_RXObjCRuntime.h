//
//  _RXObjCRuntime.h
//  RxCocoa
//
//  Created by Krunoslav Zaher on 7/11/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#import <Foundation/Foundation.h>

#if !DISABLE_SWIZZLING

/**
 ################################################################################
 This file is part of RX private API
 ################################################################################
 */

/**
 This flag controls `RELEASE` configuration behavior in case race was detecting while modifying
 ObjC runtime.

 In case this value is set to `YES`, after runtime race is detected, `abort()` will be called.
 Otherwise, only error will be reported using normal error reporting mechanism.

 In `DEBUG` mode `abort` will be always called in case race is detected.
 
 Races can't happen in case this is the only library modifying ObjC runtime, but in case there are multiple libraries
 changing ObjC runtime, race conditions can occur because there is no way to synchronize multiple libraries unaware of
 each other.

 To help remedy this situation this library will use `synchronized` on target object and it's meta-class, but
 there aren't any guarantees of how other libraries will behave.

 Default value is `NO`.

 */
extern BOOL RXAbortOnThreadingHazard;

/// Error domain for RXObjCRuntime.
extern NSString * __nonnull const RXObjCRuntimeErrorDomain;

/// `userInfo` key with additional information is interceptor probably KVO.
extern NSString * __nonnull const RXObjCRuntimeErrorIsKVOKey;

typedef NS_ENUM(NSInteger, RXObjCRuntimeError) {
    RXObjCRuntimeErrorUnknown                                           = 1,
    RXObjCRuntimeErrorObjectMessagesAlreadyBeingIntercepted             = 2,
    RXObjCRuntimeErrorSelectorNotImplemented                            = 3,
    RXObjCRuntimeErrorCantInterceptCoreFoundationTollFreeBridgedObjects = 4,
    RXObjCRuntimeErrorThreadingCollisionWithOtherInterceptionMechanism  = 5,
    RXObjCRuntimeErrorSavingOriginalForwardingMethodFailed              = 6,
    RXObjCRuntimeErrorReplacingMethodWithForwardingImplementation       = 7,
    RXObjCRuntimeErrorObservingPerformanceSensitiveMessages             = 8,
    RXObjCRuntimeErrorObservingMessagesWithUnsupportedReturnType        = 9,
};

/// Transforms normal selector into a selector with RX prefix.
SEL _Nonnull RX_selector(SEL _Nonnull selector);

/// Transforms selector into a unique pointer (because of Swift conversion rules)
void * __nonnull RX_reference_from_selector(SEL __nonnull selector);

/// Protocol that interception observers must implement.
@protocol RXMessageSentObserver

/// In case the same selector is being intercepted for a pair of base/sub classes,
/// this property will differentiate between interceptors that need to fire.
@property (nonatomic, assign, readonly) IMP __nonnull targetImplementation;

-(void)messageSentWithArguments:(NSArray* __nonnull)arguments;
-(void)methodInvokedWithArguments:(NSArray* __nonnull)arguments;

@end

/// Protocol that deallocating observer must implement.
@protocol RXDeallocatingObserver

/// In case the same selector is being intercepted for a pair of base/sub classes,
/// this property will differentiate between interceptors that need to fire.
@property (nonatomic, assign, readonly) IMP __nonnull targetImplementation;

-(void)deallocating;

@end

/// Ensures interceptor is installed on target object.
IMP __nullable RX_ensure_observing(id __nonnull target, SEL __nonnull selector, NSError *__autoreleasing __nullable * __nullable error);

/// Extracts arguments for `invocation`.
NSArray * __nonnull RX_extract_arguments(NSInvocation * __nonnull invocation);

/// Returns `YES` in case method has `void` return type.
BOOL RX_is_method_with_description_void(struct objc_method_description method);

/// Returns `YES` in case methodSignature has `void` return type.
BOOL RX_is_method_signature_void(NSMethodSignature * __nonnull methodSignature);

/// Default value for `RXInterceptionObserver.targetImplementation`.
IMP __nonnull RX_default_target_implementation(void);

#endif
