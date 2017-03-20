//
//  _RXDelegateProxy.m
//  RxCocoa
//
//  Created by Krunoslav Zaher on 7/4/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#import "include/_RXDelegateProxy.h"
#import "include/_RX.h"
#import "include/_RXObjCRuntime.h"

@interface _RXDelegateProxy () {
    id __weak __forwardToDelegate;
}

@property (nonatomic, strong) id strongForwardDelegate;

@end

static NSMutableDictionary *voidSelectorsPerClass = nil;

@implementation _RXDelegateProxy

+(NSSet*)collectVoidSelectorsForProtocol:(Protocol *)protocol {
    NSMutableSet *selectors = [NSMutableSet set];

    unsigned int protocolMethodCount = 0;
    struct objc_method_description *pMethods = protocol_copyMethodDescriptionList(protocol, NO, YES, &protocolMethodCount);

    for (unsigned int i = 0; i < protocolMethodCount; ++i) {
        struct objc_method_description method = pMethods[i];
        if (RX_is_method_with_description_void(method)) {
            [selectors addObject:SEL_VALUE(method.name)];
        }
    }
            
    free(pMethods);

    unsigned int numberOfBaseProtocols = 0;
    Protocol * __unsafe_unretained * pSubprotocols = protocol_copyProtocolList(protocol, &numberOfBaseProtocols);

    for (unsigned int i = 0; i < numberOfBaseProtocols; ++i) {
        [selectors unionSet:[self collectVoidSelectorsForProtocol:pSubprotocols[i]]];
    }
    
    free(pSubprotocols);

    return selectors;
}

+(void)initialize {
    @synchronized (_RXDelegateProxy.class) {
        if (voidSelectorsPerClass == nil) {
            voidSelectorsPerClass = [[NSMutableDictionary alloc] init];
        }

        NSMutableSet *voidSelectors = [NSMutableSet set];

#define CLASS_HIERARCHY_MAX_DEPTH 100

        NSInteger  classHierarchyDepth = 0;
        Class      targetClass         = NULL;

        for (classHierarchyDepth = 0, targetClass = self;
             classHierarchyDepth < CLASS_HIERARCHY_MAX_DEPTH && targetClass != nil;
             ++classHierarchyDepth, targetClass = class_getSuperclass(targetClass)
        ) {
            unsigned int count;
            Protocol *__unsafe_unretained *pProtocols = class_copyProtocolList(targetClass, &count);
            
            for (unsigned int i = 0; i < count; i++) {
                NSSet *selectorsForProtocol = [self collectVoidSelectorsForProtocol:pProtocols[i]];
                [voidSelectors unionSet:selectorsForProtocol];
            }
            
            free(pProtocols);
        }

        if (classHierarchyDepth == CLASS_HIERARCHY_MAX_DEPTH) {
            NSLog(@"Detected weird class hierarchy with depth over %d. Starting with this class -> %@", CLASS_HIERARCHY_MAX_DEPTH, self);
#if DEBUG
            abort();
#endif
        }
        
        voidSelectorsPerClass[CLASS_VALUE(self)] = voidSelectors;
    }
}

-(id)_forwardToDelegate {
    return __forwardToDelegate;
}

-(void)_setForwardToDelegate:(id __nullable)forwardToDelegate retainDelegate:(BOOL)retainDelegate {
    __forwardToDelegate = forwardToDelegate;
    if (retainDelegate) {
        self.strongForwardDelegate = forwardToDelegate;
    }
    else {
        self.strongForwardDelegate = nil;
    }
}

-(BOOL)hasWiredImplementationForSelector:(SEL)selector {
    return [super respondsToSelector:selector];
}

-(BOOL)voidDelegateMethodsContain:(SEL)selector {
    @synchronized(_RXDelegateProxy.class) {
        NSSet *voidSelectors = voidSelectorsPerClass[CLASS_VALUE(self.class)];
        NSAssert(voidSelectors != nil, @"Set of allowed methods not initialized");
        return [voidSelectors containsObject:SEL_VALUE(selector)];
    }
}

-(void)forwardInvocation:(NSInvocation *)anInvocation {
    BOOL isVoid = RX_is_method_signature_void(anInvocation.methodSignature);
    NSArray *arguments = nil;
    if (isVoid) {
        arguments = RX_extract_arguments(anInvocation);
        [self _sentMessage:anInvocation.selector withArguments:arguments];
    }
    
    if (self._forwardToDelegate && [self._forwardToDelegate respondsToSelector:anInvocation.selector]) {
        [anInvocation invokeWithTarget:self._forwardToDelegate];
    }

    if (isVoid) {
        [self _methodInvoked:anInvocation.selector withArguments:arguments];
    }
}

// abstract method
-(void)_sentMessage:(SEL)selector withArguments:(NSArray *)arguments {

}

// abstract method
-(void)_methodInvoked:(SEL)selector withArguments:(NSArray *)arguments {

}

-(void)dealloc {
}

@end
