//
//  PingUtil.m
//  PingUtil
//
//  Created by Rudy Yang on 2017/10/18.
//  Copyright © 2017年 Rudy Yang. All rights reserved.
//

#import "PingUtil.h"
#import "PingManager.h"

@implementation PingUtil

+ (void)pingHost:(NSString *)host success:(void(^)(NSInteger msCount))success failure:(void(^)(void))failure {
    [self pingHosts:@[host] success:^(NSArray<NSNumber *> *msCounts) {
        success([msCounts.firstObject integerValue]);
    } failure:^{
        failure();
    }];
}

+ (void)pingHosts:(NSArray<NSString *> *)hosts success:(void(^)(NSArray<NSNumber *>* msCounts))success failure:(void(^)(void))failure {
    NSMutableArray *msCounts = @[].mutableCopy;
    for (NSString *host in hosts) {
        PingManager *pingManager = [[PingManager alloc] init];
        [pingManager pingHost:host success:^(NSInteger msCount) {
            [msCounts addObject:@(msCount)];
        } failure:^{
            
        }];
    }
    success(msCounts);
}


@end
