//
//  _RXKVOObserver.h
//  RxCocoa
//
//  Created by Krunoslav Zaher on 7/11/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 ################################################################################
 This file is part of RX private API
 ################################################################################
 */

// Exists because if written in Swift, reading unowned is disabled during dealloc process
@interface _RXKVOObserver : NSObject

-(instancetype)initWithTarget:(id)target
                 retainTarget:(BOOL)retainTarget
                      keyPath:(NSString*)keyPath
                      options:(NSKeyValueObservingOptions)options
                     callback:(void (^)(id))callback;

-(void)dispose;

@end
