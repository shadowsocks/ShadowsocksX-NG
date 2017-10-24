//
//  PingUtil.h
//  PingUtil
//
//  Created by Rudy Yang on 2017/10/18.
//  Copyright © 2017年 Rudy Yang. All rights reserved.
//

#import <Foundation/Foundation.h>

FOUNDATION_EXPORT double PingUtil_maxOSVersionNumber;

FOUNDATION_EXPORT const unsigned char PingUtil_maxOSVersionString[];

@interface PingUtil : NSObject

@property (strong, nonatomic) NSMutableDictionary *pingTimers;

+ (void)pingHost:(NSString *)host success:(void(^)(NSInteger msCount))success failure:(void(^)(void))failure;

+ (void)pingHosts:(NSArray<NSString *> *)hosts success:(void(^)(NSArray<NSNumber *>* msCounts))success failure:(void(^)(void))failure;


@end
