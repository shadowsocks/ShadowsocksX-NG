//
//  PingManger.h
//  MacTool
//
//  Created by Rudy Yang on 2017/9/29.
//

#import <Foundation/Foundation.h>

@interface PingManager : NSObject

- (void)pingHost:(NSString *)host success:(void(^)(NSInteger msCount))success failure:(void(^)(void))failure;

@end
