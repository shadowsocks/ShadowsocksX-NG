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

+ (void)enablePACProxy;

+ (void)enableGlobalProxy;

+ (void)disableProxy;

+ (void)enableExternalPACProxy;

+ (void)startMonitorPAC;

@end
