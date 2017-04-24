//
//  _RXKVOObserver.m
//  RxCocoa
//
//  Created by Krunoslav Zaher on 7/11/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#import "include/_RXKVOObserver.h"

@interface _RXKVOObserver ()

@property (nonatomic, unsafe_unretained) id            target;
@property (nonatomic, strong           ) id            retainedTarget;
@property (nonatomic, copy             ) NSString     *keyPath;
@property (nonatomic, copy             ) void (^callback)(id);

@end

@implementation _RXKVOObserver

-(instancetype)initWithTarget:(id)target
                 retainTarget:(BOOL)retainTarget
                      keyPath:(NSString*)keyPath
                      options:(NSKeyValueObservingOptions)options
                     callback:(void (^)(id))callback {
    self = [super init];
    if (!self) return nil;
    
    self.target = target;
    if (retainTarget) {
        self.retainedTarget = target;
    }
    self.keyPath = keyPath;
    self.callback = callback;
    
    [self.target addObserver:self forKeyPath:self.keyPath options:options context:nil];
    
    return self;
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    @synchronized(self) {
        self.callback(change[NSKeyValueChangeNewKey]);
    }
}

-(void)dispose {
    [self.target removeObserver:self forKeyPath:self.keyPath context:nil];
    self.target = nil;
    self.retainedTarget = nil;
}

@end
