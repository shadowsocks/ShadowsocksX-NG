//
//  ProxyConfTool.m
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/29.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

#import "ProxyConfTool.h"
#import <SystemConfiguration/SystemConfiguration.h>

//https://developer.apple.com/library/mac/documentation/Networking/Conceptual/SystemConfigFrameworks/SC_Intro/SC_Intro.html

@implementation ProxyConfTool


+(NSArray*)networkServicesList {
    NSMutableArray* results = [NSMutableArray array];
    
    SCPreferencesRef prefRef = SCPreferencesCreate(nil, CFSTR("Shadowsocks"), nil);
    NSDictionary *sets = (__bridge NSDictionary *)SCPreferencesGetValue(prefRef, kSCPrefNetworkServices);
    // 遍历系统中的网络设备列表
    for (NSString *key in [sets allKeys]) {
        NSMutableDictionary *service = [sets objectForKey:key];
        NSString *userDefinedName = [service valueForKey:(__bridge NSString *)kSCPropUserDefinedName];
//        NSString *hardware = [service valueForKeyPath:@"Interface.Hardware"];
//        NSString *deviceName = [service valueForKeyPath:@"Interface.DeviceName"];
//        NSString *deviceType = [service valueForKeyPath:@"Interface.Type"];
        
        BOOL isActive = ![service objectForKey:(NSString *)kSCResvInactive];
        //                NSLog(@"%@", hardware);
//        NSLog(@"%@-------------------", key);
//        for(NSString* key in service) {
//            NSLog(@"key=%@ value=%@", key, [service objectForKey:key]);
//        }
//
        if (isActive) {
            if (isActive && userDefinedName) {
                NSDictionary* v = @{
                                    @"key": key,
                                    @"userDefinedName": userDefinedName,
                                    };
                [results addObject:v];
            }
        }
    }
    
    return results;
}


@end
