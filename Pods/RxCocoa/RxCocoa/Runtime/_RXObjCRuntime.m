//
//  _RXObjCRuntime.m
//  RxCocoa
//
//  Created by Krunoslav Zaher on 7/11/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#import <pthread.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <libkern/OSAtomic.h>
#import <stdatomic.h>

#import "include/_RX.h"
#import "include/_RXObjCRuntime.h"

// self + cmd
#define HIDDEN_ARGUMENT_COUNT   2

#if !DISABLE_SWIZZLING

#define NSErrorParam NSError *__autoreleasing __nullable * __nullable

@class RXObjCRuntime;

BOOL RXAbortOnThreadingHazard = NO;

typedef NSInvocation       *NSInvocationRef;
typedef NSMethodSignature  *NSMethodSignatureRef;
typedef unsigned char       rx_uchar;
typedef unsigned short      rx_ushort;
typedef unsigned int        rx_uint;
typedef unsigned long       rx_ulong;
typedef id (^rx_block)(id);
typedef BOOL (^RXInterceptWithOptimizedObserver)(RXObjCRuntime * __nonnull self, Class __nonnull class, SEL __nonnull selector, NSErrorParam error);

static CFTypeID  defaultTypeID;
static SEL       deallocSelector;

static int RxSwizzlingTargetClassKey = 0;

#if TRACE_RESOURCES
_Atomic static int32_t numberOInterceptedMethods = 0;
_Atomic static int32_t numberOfForwardedMethods = 0;
#endif

#define THREADING_HAZARD(class) \
    NSLog(@"There was a problem swizzling on `%@`.\nYou have probably two libraries performing swizzling in runtime.\nWe didn't want to crash your program, but this is not good ...\nYou an solve this problem by either not using swizzling in this library, removing one of those other libraries, or making sure that swizzling parts are synchronized (only perform them on main thread).\nAnd yes, this message will self destruct when you clear the console, and since it's non deterministic, the problem could still exist and it will be hard for you to reproduce it.", NSStringFromClass(class)); ABORT_IN_DEBUG if (RXAbortOnThreadingHazard) { abort(); }

#define ALWAYS(condition, message) if (!(condition)) { [NSException raise:@"RX Invalid Operator" format:@"%@", message]; }
#define ALWAYS_WITH_INFO(condition, message) NSAssert((condition), @"%@ [%@] > %@", NSStringFromClass(class), NSStringFromSelector(selector), (message))
#define C_ALWAYS(condition, message) NSCAssert((condition), @"%@ [%@] > %@", NSStringFromClass(class), NSStringFromSelector(selector), (message))

#define RX_PREFIX @"_RX_namespace_"

#define RX_ARG_id(value)           ((value) ?: [NSNull null])
#define RX_ARG_char(value)         [NSNumber numberWithChar:value]
#define RX_ARG_short(value)        [NSNumber numberWithShort:value]
#define RX_ARG_int(value)          [NSNumber numberWithInt:value]
#define RX_ARG_long(value)         [NSNumber numberWithLong:value]
#define RX_ARG_BOOL(value)         [NSNumber numberWithBool:value]
#define RX_ARG_SEL(value)          [NSNumber valueWithPointer:value]
#define RX_ARG_rx_uchar(value)     [NSNumber numberWithUnsignedInt:value]
#define RX_ARG_rx_ushort(value)    [NSNumber numberWithUnsignedInt:value]
#define RX_ARG_rx_uint(value)      [NSNumber numberWithUnsignedInt:value]
#define RX_ARG_rx_ulong(value)     [NSNumber numberWithUnsignedLong:value]
#define RX_ARG_rx_block(value)     ((id)(value) ?: [NSNull null])
#define RX_ARG_float(value)        [NSNumber numberWithFloat:value]
#define RX_ARG_double(value)       [NSNumber numberWithDouble:value]

typedef struct supported_type {
    const char *encoding;
} supported_type_t;

static supported_type_t supported_types[] = {
    { .encoding = @encode(void)},
    { .encoding = @encode(id)},
    { .encoding = @encode(Class)},
    { .encoding = @encode(void (^)(void))},
    { .encoding = @encode(char)},
    { .encoding = @encode(short)},
    { .encoding = @encode(int)},
    { .encoding = @encode(long)},
    { .encoding = @encode(long long)},
    { .encoding = @encode(unsigned char)},
    { .encoding = @encode(unsigned short)},
    { .encoding = @encode(unsigned int)},
    { .encoding = @encode(unsigned long)},
    { .encoding = @encode(unsigned long long)},
    { .encoding = @encode(float)},
    { .encoding = @encode(double)},
    { .encoding = @encode(BOOL)},
    { .encoding = @encode(const char*)},
};

NSString * __nonnull const RXObjCRuntimeErrorDomain   = @"RXObjCRuntimeErrorDomain";
NSString * __nonnull const RXObjCRuntimeErrorIsKVOKey = @"RXObjCRuntimeErrorIsKVOKey";

BOOL RX_return_type_is_supported(const char *type) {
    if (type == nil) {
        return NO;
    }

    for (int i = 0; i < sizeof(supported_types) / sizeof(supported_type_t); ++i) {
        if (supported_types[i].encoding[0] != type[0]) {
            continue;
        }
        if (strcmp(supported_types[i].encoding, type) == 0) {
            return YES;
        }
    }

    return NO;
}

static BOOL RX_method_has_supported_return_type(Method method) {
    const char *rawEncoding = method_getTypeEncoding(method);
    ALWAYS(rawEncoding != nil, @"Example encoding method is nil.");

    NSMethodSignature *methodSignature = [NSMethodSignature signatureWithObjCTypes:rawEncoding];
    ALWAYS(methodSignature != nil, @"Method signature method is nil.");

    return RX_return_type_is_supported(methodSignature.methodReturnType);
}

SEL __nonnull RX_selector(SEL __nonnull selector) {
    NSString *selectorString = NSStringFromSelector(selector);
    return NSSelectorFromString([RX_PREFIX stringByAppendingString:selectorString]);
}

#endif

BOOL RX_is_method_signature_void(NSMethodSignature * __nonnull methodSignature) {
    const char *methodReturnType = methodSignature.methodReturnType;
    return strcmp(methodReturnType, @encode(void)) == 0;
}

BOOL RX_is_method_with_description_void(struct objc_method_description method) {
    return strncmp(method.types, @encode(void), 1) == 0;
}

id __nonnull RX_extract_argument_at_index(NSInvocation * __nonnull invocation, NSUInteger index) {
    const char *argumentType = [invocation.methodSignature getArgumentTypeAtIndex:index];
    
#define RETURN_VALUE(type) \
    else if (strcmp(argumentType, @encode(type)) == 0) {\
        type val = 0; \
        [invocation getArgument:&val atIndex:index]; \
        return @(val); \
    }

    // Skip const type qualifier.
    if (argumentType[0] == 'r') {
        argumentType++;
    }
    
    if (strcmp(argumentType, @encode(id)) == 0
        || strcmp(argumentType, @encode(Class)) == 0
        || strcmp(argumentType, @encode(void (^)(void))) == 0
    ) {
        __unsafe_unretained id argument = nil;
        [invocation getArgument:&argument atIndex:index];
        return argument;
    }
    RETURN_VALUE(char)
    RETURN_VALUE(short)
    RETURN_VALUE(int)
    RETURN_VALUE(long)
    RETURN_VALUE(long long)
    RETURN_VALUE(unsigned char)
    RETURN_VALUE(unsigned short)
    RETURN_VALUE(unsigned int)
    RETURN_VALUE(unsigned long)
    RETURN_VALUE(unsigned long long)
    RETURN_VALUE(float)
    RETURN_VALUE(double)
    RETURN_VALUE(BOOL)
    RETURN_VALUE(const char *)
    else {
        NSUInteger size = 0;
        NSGetSizeAndAlignment(argumentType, &size, NULL);
        NSCParameterAssert(size > 0);
        uint8_t data[size];
        [invocation getArgument:&data atIndex:index];
        
        return [NSValue valueWithBytes:&data objCType:argumentType];
    }
}

NSArray *RX_extract_arguments(NSInvocation *invocation) {
    NSUInteger numberOfArguments = invocation.methodSignature.numberOfArguments;
    NSUInteger numberOfVisibleArguments = numberOfArguments - HIDDEN_ARGUMENT_COUNT;
    
    NSCParameterAssert(numberOfVisibleArguments >= 0);
    
    NSMutableArray *arguments = [NSMutableArray arrayWithCapacity:numberOfVisibleArguments];
    
    for (NSUInteger index = HIDDEN_ARGUMENT_COUNT; index < numberOfArguments; ++index) {
        [arguments addObject:RX_extract_argument_at_index(invocation, index) ?: [NSNull null]];
    }
    
    return arguments;
}

IMP __nonnull RX_default_target_implementation(void) {
    return _objc_msgForward;
}

#if !DISABLE_SWIZZLING

void * __nonnull RX_reference_from_selector(SEL __nonnull selector) {
    return selector;
}

static BOOL RX_forward_invocation(id __nonnull __unsafe_unretained self, NSInvocation *invocation) {
    SEL originalSelector = RX_selector(invocation.selector);

    id<RXMessageSentObserver> messageSentObserver = objc_getAssociatedObject(self, originalSelector);

    if (messageSentObserver != nil) {
        NSArray *arguments = RX_extract_arguments(invocation);
        [messageSentObserver messageSentWithArguments:arguments];
    }

    if ([self respondsToSelector:originalSelector]) {
        invocation.selector = originalSelector;
        [invocation invokeWithTarget:self];

        if (messageSentObserver != nil) {
            NSArray *arguments = RX_extract_arguments(invocation);
            [messageSentObserver methodInvokedWithArguments:arguments];
        }

        return YES;
    }

    return NO;
}

static BOOL RX_responds_to_selector(id __nonnull __unsafe_unretained self, SEL selector) {
    Class class = object_getClass(self);
    if (class == nil) { return NO; }

    Method m = class_getInstanceMethod(class, selector);
    return m != nil;

}

static NSMethodSignatureRef RX_method_signature(id __nonnull __unsafe_unretained self, SEL selector) {
    Class class = object_getClass(self);
    if (class == nil) { return nil; }

    Method method = class_getInstanceMethod(class, selector);
    if (method == nil) { return nil; }

    const char *encoding = method_getTypeEncoding(method);
    if (encoding == nil) { return nil; }

    return [NSMethodSignature signatureWithObjCTypes:encoding];
}

static NSString * __nonnull RX_method_encoding(Method __nonnull method) {
    const char *typeEncoding = method_getTypeEncoding(method);
    ALWAYS(typeEncoding != nil, @"Method encoding is nil.");

    NSString *encoding = [NSString stringWithCString:typeEncoding encoding:NSASCIIStringEncoding];
    ALWAYS(encoding != nil, @"Can't convert encoding to NSString.");
    return encoding;
}

@interface RXObjCRuntime: NSObject

@property (nonatomic, assign) pthread_mutex_t lock;

@property (nonatomic, strong) NSMutableSet<NSValue *> *classesThatSupportObservingByForwarding;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSMutableSet<NSValue*> *> *forwardedSelectorsByClass;

@property (nonatomic, strong) NSMutableDictionary<NSValue *, Class> *dynamicSubclassByRealClass;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSMutableDictionary<NSValue*, NSValue *>*> *interceptorIMPbySelectorsByClass;

+(RXObjCRuntime*)instance;

-(void)performLocked:(void (^)(RXObjCRuntime* __nonnull))action;
-(IMP __nullable)ensurePrepared:(id __nonnull)target forObserving:(SEL __nonnull)selector error:(NSErrorParam)error;
-(BOOL)ensureSwizzledSelector:(SEL __nonnull)selector
                      ofClass:(Class __nonnull)class
   newImplementationGenerator:(IMP(^)(void))newImplementationGenerator
replacementImplementationGenerator:(IMP (^)(IMP originalImplementation))replacementImplementationGenerator
                        error:(NSErrorParam)error;


+(void)registerOptimizedObserver:(RXInterceptWithOptimizedObserver)registration encodedAs:(SEL)selector;

@end

/**
 All API methods perform work on locked instance of `RXObjCRuntime`. In that way it's easy to prove
 that every action is properly locked.
 */
IMP __nullable RX_ensure_observing(id __nonnull target, SEL __nonnull selector, NSErrorParam error) {
    __block IMP targetImplementation = nil;
    // Target is the second object that needs to be synchronized to TRY to make sure other swizzling framework
    // won't do something in parallel.
    // Even though this is too fine grained locking and more coarse grained locks should exist, this is just in case
    // someone calls this method directly without any external lock.
    @synchronized(target) {
        // The only other resource that all other swizzling libraries have in common without introducing external
        // dependencies is class object.
        //
        // It is polite to try to synchronize it in hope other unknown entities will also attempt to do so.
        // It's like trying to figure out how to communicate with aliens without actually communicating,
        // save for the fact that aliens are people, programmers, authors of swizzling libraries.
        @synchronized([target class]) {
            [[RXObjCRuntime instance] performLocked:^(RXObjCRuntime * __nonnull self) {
                targetImplementation = [self ensurePrepared:target
                                               forObserving:selector
                                                      error:error];
            }];
        }
    }

    return targetImplementation;
}

// bodies

#define FORWARD_BODY(invocation)                        if (RX_forward_invocation(self, NAME_CAT(_, 0, invocation))) { return; }

#define RESPONDS_TO_SELECTOR_BODY(selector)             if (RX_responds_to_selector(self, NAME_CAT(_, 0, selector))) return YES;

#define CLASS_BODY(...)                                 return actAsClass;

#define METHOD_SIGNATURE_FOR_SELECTOR_BODY(selector)                                            \
    NSMethodSignatureRef methodSignature = RX_method_signature(self, NAME_CAT(_, 0, selector)); \
    if (methodSignature != nil) {                                                               \
        return methodSignature;                                                                 \
    }

#define DEALLOCATING_BODY(...)                                                        \
    id<RXDeallocatingObserver> observer = objc_getAssociatedObject(self, rxSelector); \
    if (observer != nil && observer.targetImplementation == thisIMP) {                \
        [observer deallocating];                                                      \
    }

#define OBSERVE_BODY(...)                                                              \
    id<RXMessageSentObserver> observer = objc_getAssociatedObject(self, rxSelector);   \
                                                                                       \
    if (observer != nil && observer.targetImplementation == thisIMP) {                 \
        [observer messageSentWithArguments:@[COMMA_DELIMITED_ARGUMENTS(__VA_ARGS__)]]; \
    }                                                                                  \


#define OBSERVE_INVOKED_BODY(...)                                                        \
    if (observer != nil && observer.targetImplementation == thisIMP) {                   \
        [observer methodInvokedWithArguments:@[COMMA_DELIMITED_ARGUMENTS(__VA_ARGS__)]]; \
    }                                                                                    \


#define BUILD_ARG_WRAPPER(type)                   RX_ARG_ ## type                                                     //RX_ARG_ ## type

#define CAT(_1, _2, head, tail)                   RX_CAT2(head, tail)
#define SEPARATE_BY_COMMA(_1, _2, head, tail)     head, tail
#define SEPARATE_BY_SPACE(_1, _2, head, tail)     head tail
#define SEPARATE_BY_UNDERSCORE(head, tail)        RX_CAT2(RX_CAT2(head, _), tail)

#define UNDERSCORE_TYPE_CAT(_1, index, type)      RX_CAT2(_, type)                                                    // generates -> _type
#define NAME_CAT(_1, index, type)                 SEPARATE_BY_UNDERSCORE(type, index)                                 // generates -> type_0
#define TYPE_AND_NAME_CAT(_1, index, type)        type SEPARATE_BY_UNDERSCORE(type, index)                            // generates -> type type_0
#define NOT_NULL_ARGUMENT_CAT(_1, index, type)    BUILD_ARG_WRAPPER(type)(NAME_CAT(_1, index, type))                  // generates -> ((id)(type_0) ?: [NSNull null])
#define EXAMPLE_PARAMETER(_1, index, type)        RX_CAT2(_, type):(type)SEPARATE_BY_UNDERSCORE(type, index)          // generates -> _type:(type)type_0
#define SELECTOR_PART(_1, index, type)            RX_CAT2(_, type:)                                                   // generates -> _type:

#define COMMA_DELIMITED_ARGUMENTS(...)            RX_FOREACH(_, SEPARATE_BY_COMMA, NOT_NULL_ARGUMENT_CAT, ## __VA_ARGS__)
#define ARGUMENTS(...)                            RX_FOREACH_COMMA(_, NAME_CAT, ## __VA_ARGS__)
#define DECLARE_ARGUMENTS(...)                    RX_FOREACH_COMMA(_, TYPE_AND_NAME_CAT, ## __VA_ARGS__)

// optimized observe methods

#define GENERATE_METHOD_IDENTIFIER(...)          RX_CAT2(swizzle, RX_FOREACH(_, CAT, UNDERSCORE_TYPE_CAT, ## __VA_ARGS__))

#define GENERATE_OBSERVE_METHOD_DECLARATION(...)                                 \
    -(BOOL)GENERATE_METHOD_IDENTIFIER(__VA_ARGS__):(Class __nonnull)class        \
                                          selector:(SEL)selector                 \
                                             error:(NSErrorParam)error {         \


#define BUILD_EXAMPLE_METHOD(return_value, ...) \
    +(return_value)RX_CAT2(RX_CAT2(example_, return_value), RX_FOREACH(_, SEPARATE_BY_SPACE, EXAMPLE_PARAMETER, ## __VA_ARGS__)) {}

#define BUILD_EXAMPLE_METHOD_SELECTOR(return_value, ...) \
    RX_CAT2(RX_CAT2(example_, return_value), RX_FOREACH(_, SEPARATE_BY_SPACE, SELECTOR_PART, ## __VA_ARGS__))

#define SWIZZLE_OBSERVE_METHOD(return_value, ...)                                                                                                       \
    @interface RXObjCRuntime (GENERATE_METHOD_IDENTIFIER(return_value, ## __VA_ARGS__))                                                                 \
    @end                                                                                                                                                \
                                                                                                                                                        \
    @implementation RXObjCRuntime(GENERATE_METHOD_IDENTIFIER(return_value, ## __VA_ARGS__))                                                             \
    BUILD_EXAMPLE_METHOD(return_value, ## __VA_ARGS__)                                                                                                  \
    SWIZZLE_METHOD(return_value, GENERATE_OBSERVE_METHOD_DECLARATION(return_value, ## __VA_ARGS__), OBSERVE_BODY, OBSERVE_INVOKED_BODY, ## __VA_ARGS__) \
                                                                                                                                                        \
    +(void)load {                                                                                                                                       \
       __unused SEL exampleSelector = @selector(BUILD_EXAMPLE_METHOD_SELECTOR(return_value, ## __VA_ARGS__));                                           \
       [self registerOptimizedObserver:^BOOL(RXObjCRuntime * __nonnull self, Class __nonnull class,                                                     \
            SEL __nonnull selector, NSErrorParam error) {                                                                                               \
            return [self GENERATE_METHOD_IDENTIFIER(return_value, ## __VA_ARGS__):class selector:selector error:error];                                 \
       } encodedAs:exampleSelector];                                                                                                                    \
    }                                                                                                                                                   \
                                                                                                                                                        \
    @end                                                                                                                                                \

// infrastructure method

#define NO_BODY(...)

#define SWIZZLE_INFRASTRUCTURE_METHOD(return_value, method_name, parameters, method_selector, body, ...)               \
    SWIZZLE_METHOD(return_value, -(BOOL)method_name:(Class __nonnull)class parameters error:(NSErrorParam)error        \
        {                                                                                                              \
            SEL selector = method_selector; , body, NO_BODY, __VA_ARGS__)                                              \


// common base

#define SWIZZLE_METHOD(return_value, method_prototype, body, invoked_body, ...)                                          \
method_prototype                                                                                                         \
    __unused SEL rxSelector = RX_selector(selector);                                                                     \
    IMP (^newImplementationGenerator)(void) = ^() {                                                                          \
        __block IMP thisIMP = nil;                                                                                       \
        id newImplementation = ^return_value(__unsafe_unretained id self DECLARE_ARGUMENTS(__VA_ARGS__)) {               \
            body(__VA_ARGS__)                                                                                            \
                                                                                                                         \
            struct objc_super superInfo = {                                                                              \
                .receiver = self,                                                                                        \
                .super_class = class_getSuperclass(class)                                                                \
            };                                                                                                           \
                                                                                                                         \
            return_value (*msgSend)(struct objc_super *, SEL DECLARE_ARGUMENTS(__VA_ARGS__))                             \
                = (__typeof__(msgSend))objc_msgSendSuper;                                                                \
            @try {                                                                                                       \
              return msgSend(&superInfo, selector ARGUMENTS(__VA_ARGS__));                                               \
            }                                                                                                            \
            @finally { invoked_body(__VA_ARGS__) }                                                                       \
        };                                                                                                               \
                                                                                                                         \
        thisIMP = imp_implementationWithBlock(newImplementation);                                                        \
        return thisIMP;                                                                                                  \
    };                                                                                                                   \
                                                                                                                         \
    IMP (^replacementImplementationGenerator)(IMP) = ^(IMP originalImplementation) {                                     \
        __block return_value (*originalImplementationTyped)(__unsafe_unretained id, SEL DECLARE_ARGUMENTS(__VA_ARGS__) ) \
            = (__typeof__(originalImplementationTyped))(originalImplementation);                                         \
                                                                                                                         \
        __block IMP thisIMP = nil;                                                                                       \
        id implementationReplacement = ^return_value(__unsafe_unretained id self DECLARE_ARGUMENTS(__VA_ARGS__) ) {      \
            body(__VA_ARGS__)                                                                                            \
            @try {                                                                                                       \
                return originalImplementationTyped(self, selector ARGUMENTS(__VA_ARGS__));                               \
            }                                                                                                            \
            @finally { invoked_body(__VA_ARGS__) }                                                                       \
        };                                                                                                               \
                                                                                                                         \
        thisIMP = imp_implementationWithBlock(implementationReplacement);                                                \
        return thisIMP;                                                                                                  \
    };                                                                                                                   \
                                                                                                                         \
    return [self ensureSwizzledSelector:selector                                                                         \
                                ofClass:class                                                                            \
             newImplementationGenerator:newImplementationGenerator                                                       \
     replacementImplementationGenerator:replacementImplementationGenerator                                               \
                                  error:error];                                                                          \
 }                                                                                                                       \


@interface RXObjCRuntime (InfrastructureMethods)
@end

// MARK: Infrastructure Methods

@implementation RXObjCRuntime (InfrastructureMethods)

SWIZZLE_INFRASTRUCTURE_METHOD(
    void,
    swizzleForwardInvocation,
    ,
    @selector(forwardInvocation:),
    FORWARD_BODY,
    NSInvocationRef
)
SWIZZLE_INFRASTRUCTURE_METHOD(
    BOOL,
    swizzleRespondsToSelector,
    ,
    @selector(respondsToSelector:),
    RESPONDS_TO_SELECTOR_BODY,
    SEL
)
SWIZZLE_INFRASTRUCTURE_METHOD(
    Class __nonnull,
    swizzleClass,
    toActAs:(Class)actAsClass,
    @selector(class),
    CLASS_BODY
)
SWIZZLE_INFRASTRUCTURE_METHOD(
    NSMethodSignatureRef,
    swizzleMethodSignatureForSelector,
    ,
    @selector(methodSignatureForSelector:),
    METHOD_SIGNATURE_FOR_SELECTOR_BODY,
    SEL
)
SWIZZLE_INFRASTRUCTURE_METHOD(
    void,
    swizzleDeallocating,
    ,
    deallocSelector,
    DEALLOCATING_BODY
)

@end

// MARK: Optimized intercepting methods for specific combination of parameter types

SWIZZLE_OBSERVE_METHOD(void)

SWIZZLE_OBSERVE_METHOD(void, id)
SWIZZLE_OBSERVE_METHOD(void, char)
SWIZZLE_OBSERVE_METHOD(void, short)
SWIZZLE_OBSERVE_METHOD(void, int)
SWIZZLE_OBSERVE_METHOD(void, long)
SWIZZLE_OBSERVE_METHOD(void, rx_uchar)
SWIZZLE_OBSERVE_METHOD(void, rx_ushort)
SWIZZLE_OBSERVE_METHOD(void, rx_uint)
SWIZZLE_OBSERVE_METHOD(void, rx_ulong)
SWIZZLE_OBSERVE_METHOD(void, rx_block)
SWIZZLE_OBSERVE_METHOD(void, float)
SWIZZLE_OBSERVE_METHOD(void, double)
SWIZZLE_OBSERVE_METHOD(void, SEL)

SWIZZLE_OBSERVE_METHOD(void, id, id)
SWIZZLE_OBSERVE_METHOD(void, id, char)
SWIZZLE_OBSERVE_METHOD(void, id, short)
SWIZZLE_OBSERVE_METHOD(void, id, int)
SWIZZLE_OBSERVE_METHOD(void, id, long)
SWIZZLE_OBSERVE_METHOD(void, id, rx_uchar)
SWIZZLE_OBSERVE_METHOD(void, id, rx_ushort)
SWIZZLE_OBSERVE_METHOD(void, id, rx_uint)
SWIZZLE_OBSERVE_METHOD(void, id, rx_ulong)
SWIZZLE_OBSERVE_METHOD(void, id, rx_block)
SWIZZLE_OBSERVE_METHOD(void, id, float)
SWIZZLE_OBSERVE_METHOD(void, id, double)
SWIZZLE_OBSERVE_METHOD(void, id, SEL)

// MARK: RXObjCRuntime

@implementation RXObjCRuntime

static RXObjCRuntime *_instance = nil;
static NSMutableDictionary<NSString *, RXInterceptWithOptimizedObserver> *optimizedObserversByMethodEncoding = nil;

+(RXObjCRuntime*)instance {
    return _instance;
}

+(void)initialize {
    _instance = [[RXObjCRuntime alloc] init];
    defaultTypeID = CFGetTypeID((CFTypeRef)RXObjCRuntime.class); // just need a reference of some object not from CF
    deallocSelector = NSSelectorFromString(@"dealloc");
    NSAssert(_instance != nil, @"Failed to initialize swizzling");
}

-(instancetype)init {
    self = [super init];
    if (!self) return nil;

    self.classesThatSupportObservingByForwarding = [NSMutableSet set];
    self.forwardedSelectorsByClass = [NSMutableDictionary dictionary];

    self.dynamicSubclassByRealClass = [NSMutableDictionary dictionary];
    self.interceptorIMPbySelectorsByClass = [NSMutableDictionary dictionary];

    pthread_mutexattr_t lock_attr;
    pthread_mutexattr_init(&lock_attr);
    pthread_mutexattr_settype(&lock_attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&_lock, &lock_attr);
    pthread_mutexattr_destroy(&lock_attr);
    
    return self;
}

-(void)performLocked:(void (^)(RXObjCRuntime* __nonnull))action {
    pthread_mutex_lock(&_lock);
    action(self);
    pthread_mutex_unlock(&_lock);
}

+(void)registerOptimizedObserver:(RXInterceptWithOptimizedObserver)registration encodedAs:(SEL)selector {
    Method exampleEncodingMethod = class_getClassMethod(self, selector);
    ALWAYS(exampleEncodingMethod != nil, @"Example encoding method is nil.");

    NSString *methodEncoding = RX_method_encoding(exampleEncodingMethod);

    if (optimizedObserversByMethodEncoding == nil) {
        optimizedObserversByMethodEncoding = [NSMutableDictionary dictionary];
    }

    DLOG(@"Added optimized method: %@ (%@)", methodEncoding, NSStringFromSelector(selector));
    ALWAYS(optimizedObserversByMethodEncoding[methodEncoding] == nil, @"Optimized observer already registered")
    optimizedObserversByMethodEncoding[methodEncoding] = registration;
}

/**
 This is the main entry point for observing messages sent to arbitrary objects.
 */
-(IMP __nullable)ensurePrepared:(id __nonnull)target forObserving:(SEL __nonnull)selector error:(NSErrorParam)error {
    Method instanceMethod = class_getInstanceMethod([target class], selector);
    if (instanceMethod == nil) {
        RX_THROW_ERROR([NSError errorWithDomain:RXObjCRuntimeErrorDomain
                                           code:RXObjCRuntimeErrorSelectorNotImplemented
                                       userInfo:nil], nil);
    }

    if (selector == @selector(class)
    ||  selector == @selector(forwardingTargetForSelector:)
    ||  selector == @selector(methodSignatureForSelector:)
    ||  selector == @selector(respondsToSelector:)) {
        RX_THROW_ERROR([NSError errorWithDomain:RXObjCRuntimeErrorDomain
                                           code:RXObjCRuntimeErrorObservingPerformanceSensitiveMessages
                                       userInfo:nil], nil);
    }

    // For `dealloc` message, original implementation will be swizzled.
    // This is a special case because observing `dealloc` message is performed when `observeWeakly` is used.
    //
    // Some toll free bridged classes don't handle `object_setClass` well and cause crashes.
    //
    // To make `deallocating` as robust as possible, original implementation will be replaced.
    if (selector == deallocSelector) {
        Class __nonnull deallocSwizzingTarget = [target class];
        IMP interceptorIMPForSelector = [self interceptorImplementationForSelector:selector forClass:deallocSwizzingTarget];
        if (interceptorIMPForSelector != nil) {
            return interceptorIMPForSelector;
        }

        if (![self swizzleDeallocating:deallocSwizzingTarget error:error]) {
            return nil;
        }

        interceptorIMPForSelector = [self interceptorImplementationForSelector:selector forClass:deallocSwizzingTarget];
        if (interceptorIMPForSelector != nil) {
            return interceptorIMPForSelector;
        }
    }
    else {
        Class __nullable swizzlingImplementorClass = [self prepareTargetClassForObserving:target error:error];
        if (swizzlingImplementorClass == nil) {
            return nil;
        }

        NSString *methodEncoding = RX_method_encoding(instanceMethod);
        RXInterceptWithOptimizedObserver optimizedIntercept = optimizedObserversByMethodEncoding[methodEncoding];

        if (!RX_method_has_supported_return_type(instanceMethod)) {
            RX_THROW_ERROR([NSError errorWithDomain:RXObjCRuntimeErrorDomain
                                               code:RXObjCRuntimeErrorObservingMessagesWithUnsupportedReturnType
                                           userInfo:nil], nil);
        }

        // optimized interception method
        if (optimizedIntercept != nil) {
            IMP interceptorIMPForSelector = [self interceptorImplementationForSelector:selector forClass:swizzlingImplementorClass];
            if (interceptorIMPForSelector != nil) {
                return interceptorIMPForSelector;
            }

            if (!optimizedIntercept(self, swizzlingImplementorClass, selector, error)) {
                return nil;
            }

            interceptorIMPForSelector = [self interceptorImplementationForSelector:selector forClass:swizzlingImplementorClass];
            if (interceptorIMPForSelector != nil) {
                return interceptorIMPForSelector;
            }
        }
        // default fallback to observing by forwarding messages
        else {
            if ([self forwardingSelector:selector forClass:swizzlingImplementorClass]) {
                return RX_default_target_implementation();
            }

            if (![self observeByForwardingMessages:swizzlingImplementorClass
                                          selector:selector
                                            target:target
                                             error:error]) {
                return nil;
            }

            if ([self forwardingSelector:selector forClass:swizzlingImplementorClass]) {
                return RX_default_target_implementation();
            }
        }
    }

    RX_THROW_ERROR([NSError errorWithDomain:RXObjCRuntimeErrorDomain
                                       code:RXObjCRuntimeErrorUnknown
                                   userInfo:nil], nil);
}

-(Class __nullable)prepareTargetClassForObserving:(id __nonnull)target error:(NSErrorParam)error {
    Class swizzlingClass = objc_getAssociatedObject(target, &RxSwizzlingTargetClassKey);
    if (swizzlingClass != nil) {
        return swizzlingClass;
    }

    Class __nonnull wannaBeClass = [target class];
    /**
     Core Foundation classes are usually toll free bridged. Those classes crash the program in case
     `object_setClass` is performed on them.

     There is a possibility to just swizzle methods on original object, but since those won't be usual use
     cases for this library, then an error will just be reported for now.
     */
    BOOL isThisTollFreeFoundationClass = CFGetTypeID((CFTypeRef)target) != defaultTypeID;

    if (isThisTollFreeFoundationClass) {
        RX_THROW_ERROR([NSError errorWithDomain:RXObjCRuntimeErrorDomain
                                           code:RXObjCRuntimeErrorCantInterceptCoreFoundationTollFreeBridgedObjects
                                       userInfo:nil], nil);
    }

    /**
     If the object is reporting a different class then what it's real class, that means that there is probably
     already some interception mechanism in place or something weird is happening.
     
     Most common case when this would happen is when using KVO (`observe`) and `sentMessage`.

     This error is easily resolved by just using `sentMessage` observing before `observe`.
     
     The reason why other way around could create issues is because KVO will unregister it's interceptor 
     class and restore original class. Unfortunately that will happen no matter was there another interceptor
     subclass registered in hierarchy or not.
     
     Failure scenario:
     * KVO sets class to be `__KVO__OriginalClass` (subclass of `OriginalClass`)
     * `sentMessage` sets object class to be `_RX_namespace___KVO__OriginalClass` (subclass of `__KVO__OriginalClass`)
     * then unobserving with KVO will restore class to be `OriginalClass` -> failure point

     The reason why changing order of observing works is because any interception method should return
     object's original real class (if that doesn't happen then it's really easy to argue that's a bug
     in that other library).
     
     This library won't remove registered interceptor even if there aren't any observers left because
     it's highly unlikely it would have any benefit in real world use cases, and it's even more
     dangerous.
     */
    if ([target class] != object_getClass(target)) {
        BOOL isKVO = [target respondsToSelector:NSSelectorFromString(@"_isKVOA")];

        RX_THROW_ERROR([NSError errorWithDomain:RXObjCRuntimeErrorDomain
                                           code:RXObjCRuntimeErrorObjectMessagesAlreadyBeingIntercepted
                                       userInfo:@{
                                                  RXObjCRuntimeErrorIsKVOKey : @(isKVO)
                                                  }], nil);
    }

    Class __nullable dynamicFakeSubclass = [self ensureHasDynamicFakeSubclass:wannaBeClass error:error];

    if (dynamicFakeSubclass == nil) {
        return nil;
    }

    Class previousClass = object_setClass(target, dynamicFakeSubclass);
    if (previousClass != wannaBeClass) {
        THREADING_HAZARD(wannaBeClass);
        RX_THROW_ERROR([NSError errorWithDomain:RXObjCRuntimeErrorDomain
                                           code:RXObjCRuntimeErrorThreadingCollisionWithOtherInterceptionMechanism
                                       userInfo:nil], nil);
    }

    objc_setAssociatedObject(target, &RxSwizzlingTargetClassKey, dynamicFakeSubclass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return dynamicFakeSubclass;
}


-(BOOL)forwardingSelector:(SEL)selector forClass:(Class __nonnull)class {
    return [self.forwardedSelectorsByClass[CLASS_VALUE(class)] containsObject:SEL_VALUE(selector)];
}

-(void)registerForwardedSelector:(SEL)selector forClass:(Class __nonnull)class {
    NSValue *classValue = CLASS_VALUE(class);

    NSMutableSet<NSValue *> *forwardedSelectors = self.forwardedSelectorsByClass[classValue];

    if (forwardedSelectors == nil) {
        forwardedSelectors = [NSMutableSet set];
        self.forwardedSelectorsByClass[classValue] = forwardedSelectors;
    }

    [forwardedSelectors addObject:SEL_VALUE(selector)];
}

-(BOOL)observeByForwardingMessages:(Class __nonnull)swizzlingImplementorClass
                          selector:(SEL)selector
                            target:(id __nonnull)target
                             error:(NSErrorParam)error {
    if (![self ensureForwardingMethodsAreSwizzled:swizzlingImplementorClass error:error]) {
        return NO;
    }

    ALWAYS(![self forwardingSelector:selector forClass:swizzlingImplementorClass], @"Already observing selector for class");

#if TRACE_RESOURCES
    atomic_fetch_add(&numberOfForwardedMethods, 1);
#endif
    SEL rxSelector = RX_selector(selector);

    Method instanceMethod = class_getInstanceMethod(swizzlingImplementorClass, selector);
    ALWAYS(instanceMethod != nil, @"Instance method is nil");

    const char* methodEncoding = method_getTypeEncoding(instanceMethod);
    ALWAYS(methodEncoding != nil, @"Method encoding is nil.");
    NSMethodSignature *methodSignature = [NSMethodSignature signatureWithObjCTypes:methodEncoding];
    ALWAYS(methodSignature != nil, @"Method signature is invalid.");

    IMP implementation = method_getImplementation(instanceMethod);

    if (implementation == nil) {
        RX_THROW_ERROR([NSError errorWithDomain:RXObjCRuntimeErrorDomain
                                           code:RXObjCRuntimeErrorSelectorNotImplemented
                                       userInfo:nil], NO);
    }

    if (!class_addMethod(swizzlingImplementorClass, rxSelector, implementation, methodEncoding)) {
        RX_THROW_ERROR([NSError errorWithDomain:RXObjCRuntimeErrorDomain
                                           code:RXObjCRuntimeErrorSavingOriginalForwardingMethodFailed
                                       userInfo:nil], NO);
    }

    if (!class_addMethod(swizzlingImplementorClass, selector, _objc_msgForward, methodEncoding)) {
        if (implementation != method_setImplementation(instanceMethod, _objc_msgForward)) {
            THREADING_HAZARD(swizzlingImplementorClass);
            RX_THROW_ERROR([NSError errorWithDomain:RXObjCRuntimeErrorDomain
                                               code:RXObjCRuntimeErrorReplacingMethodWithForwardingImplementation
                                           userInfo:nil], NO);
        }
    }

    DLOG(@"Rx uses forwarding to observe `%@` for `%@`.", NSStringFromSelector(selector), swizzlingImplementorClass);
    [self registerForwardedSelector:selector forClass:swizzlingImplementorClass];

    return YES;
}

/**
 If object don't have some weird behavior, claims it's the same class that runtime shows,
 then dynamic subclass is created (only this instance will have performance hit).
 
 In case something weird is detected, then original base class is being swizzled and all instances
 will have somewhat reduced performance.
 
 This is especially handy optimization for weak KVO. Nobody will swizzle for example `NSString`,
 but to know when instance of a `NSString` was deallocated, performance hit will be only felt on a 
 single instance of `NSString`, not all instances of `NSString`s.
 */
-(Class __nullable)ensureHasDynamicFakeSubclass:(Class __nonnull)class error:(NSErrorParam)error {
    Class dynamicFakeSubclass = self.dynamicSubclassByRealClass[CLASS_VALUE(class)];
    if (dynamicFakeSubclass != nil) {
        return dynamicFakeSubclass;
    }

    NSString *dynamicFakeSubclassName = [RX_PREFIX stringByAppendingString:NSStringFromClass(class)];
    const char *dynamicFakeSubclassNameRaw = dynamicFakeSubclassName.UTF8String;
    dynamicFakeSubclass = objc_allocateClassPair(class, dynamicFakeSubclassNameRaw, 0);
    ALWAYS(dynamicFakeSubclass != nil, @"Class not generated");

    if (![self swizzleClass:dynamicFakeSubclass toActAs:class error:error]) {
        return nil;
    }

    objc_registerClassPair(dynamicFakeSubclass);

    [self.dynamicSubclassByRealClass setObject:dynamicFakeSubclass forKey:CLASS_VALUE(class)];
    ALWAYS(self.dynamicSubclassByRealClass[CLASS_VALUE(class)] != nil, @"Class not registered");

    return dynamicFakeSubclass;
}

-(BOOL)ensureForwardingMethodsAreSwizzled:(Class __nonnull)class error:(NSErrorParam)error {
    NSValue *classValue = CLASS_VALUE(class);
    if ([self.classesThatSupportObservingByForwarding containsObject:classValue]) {
        return YES;
    }

    if (![self swizzleForwardInvocation:class error:error]) { return NO; }
    if (![self swizzleMethodSignatureForSelector:class error:error]) { return NO; }
    if (![self swizzleRespondsToSelector:class error:error]) { return NO; }

    [self.classesThatSupportObservingByForwarding addObject:classValue];

    return YES;
}

-(void)registerInterceptedSelector:(SEL)selector implementation:(IMP)implementation forClass:(Class)class {
    NSValue * __nonnull classValue = CLASS_VALUE(class);
    NSValue * __nonnull selectorValue = SEL_VALUE(selector);

    NSMutableDictionary *swizzledIMPBySelectorsForClass = self.interceptorIMPbySelectorsByClass[classValue];

    if (swizzledIMPBySelectorsForClass == nil) {
        swizzledIMPBySelectorsForClass = [NSMutableDictionary dictionary];
        self.interceptorIMPbySelectorsByClass[classValue] = swizzledIMPBySelectorsForClass;
    }

    swizzledIMPBySelectorsForClass[selectorValue] = IMP_VALUE(implementation);

    ALWAYS([self interceptorImplementationForSelector:selector forClass:class] != nil, @"Class should have been swizzled");
}

-(IMP)interceptorImplementationForSelector:(SEL)selector forClass:(Class)class {
    NSValue * __nonnull classValue = CLASS_VALUE(class);
    NSValue * __nonnull selectorValue = SEL_VALUE(selector);

    NSMutableDictionary *swizzledIMPBySelectorForClass = self.interceptorIMPbySelectorsByClass[classValue];

    NSValue *impValue = swizzledIMPBySelectorForClass[selectorValue];
    return impValue.pointerValue;
}

-(BOOL)ensureSwizzledSelector:(SEL __nonnull)selector
                      ofClass:(Class __nonnull)class
   newImplementationGenerator:(IMP(^)(void))newImplementationGenerator
replacementImplementationGenerator:(IMP (^)(IMP originalImplementation))replacementImplementationGenerator
                        error:(NSErrorParam)error {
    if ([self interceptorImplementationForSelector:selector forClass:class] != nil) {
        DLOG(@"Trying to register same intercept at least once, this sounds like a possible bug");
        return YES;
    }

#if TRACE_RESOURCES
    atomic_fetch_add(&numberOInterceptedMethods, 1);
#endif
    
    DLOG(@"Rx is swizzling `%@` for `%@`", NSStringFromSelector(selector), class);

    Method existingMethod = class_getInstanceMethod(class, selector);
    ALWAYS(existingMethod != nil, @"Method doesn't exist");

    const char *encoding = method_getTypeEncoding(existingMethod);
    ALWAYS(encoding != nil, @"Encoding is nil");

    IMP newImplementation = newImplementationGenerator();

    if (class_addMethod(class, selector, newImplementation, encoding)) {
        // new method added, job done
        [self registerInterceptedSelector:selector implementation:newImplementation forClass:class];

        return YES;
    }

    imp_removeBlock(newImplementation);

    // if add fails, that means that method already exists on targetClass
    Method existingMethodOnTargetClass = existingMethod;

    IMP originalImplementation = method_getImplementation(existingMethodOnTargetClass);
    ALWAYS(originalImplementation != nil, @"Method must exist.");
    IMP implementationReplacementIMP = replacementImplementationGenerator(originalImplementation);
    ALWAYS(implementationReplacementIMP != nil, @"Method must exist.");
    IMP originalImplementationAfterChange = method_setImplementation(existingMethodOnTargetClass, implementationReplacementIMP);
    ALWAYS(originalImplementation != nil, @"Method must exist.");

    // If method replacing failed, who knows what happened, better not trying again, otherwise program can get
    // corrupted.
    [self registerInterceptedSelector:selector implementation:implementationReplacementIMP forClass:class];

    // ¯\_(ツ)_/¯
    if (originalImplementationAfterChange != originalImplementation) {
        THREADING_HAZARD(class);
        return NO;
    }

    return YES;
}

@end

#if TRACE_RESOURCES

NSInteger RX_number_of_dynamic_subclasses() {
    __block NSInteger count = 0;
    [[RXObjCRuntime instance] performLocked:^(RXObjCRuntime * __nonnull self) {
        count = self.dynamicSubclassByRealClass.count;
    }];

    return count;
}

NSInteger RX_number_of_forwarding_enabled_classes() {
    __block NSInteger count = 0;
    [[RXObjCRuntime instance] performLocked:^(RXObjCRuntime * __nonnull self) {
        count = self.classesThatSupportObservingByForwarding.count;
    }];

    return count;
}

NSInteger RX_number_of_intercepting_classes() {
    __block NSInteger count = 0;
    [[RXObjCRuntime instance] performLocked:^(RXObjCRuntime * __nonnull self) {
        count = self.interceptorIMPbySelectorsByClass.count;
    }];

    return count;
}

NSInteger RX_number_of_forwarded_methods() {
    return numberOfForwardedMethods;
}

NSInteger RX_number_of_swizzled_methods() {
    return numberOInterceptedMethods;
}

#endif

#endif
