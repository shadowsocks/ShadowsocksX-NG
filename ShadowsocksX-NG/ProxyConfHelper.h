//
//  ProxyConfHelper.h
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/10.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GCDWebServer/GCDWebServer.h>
#import <GCDWebServer/GCDWebServerDataResponse.h>

@interface ProxyConfHelper : NSObject

+ (void)install;

+ (void)enablePACProxy:(NSString*) PACFilePath;

+ (void)enableGlobalProxy;

+ (void)disableProxy:(NSString*) PACFilePath;

+ (NSString*)startPACServer:(NSString*) PACFilePath;

+ (void)stopPACServer;

+ (void)enableWhiteListProxy;

@end
