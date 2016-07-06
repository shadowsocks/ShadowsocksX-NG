//
//  main.m
//  shadowsocks_sysconf
//
//  Created by clowwindy on 14-3-15.
//  Copyright (c) 2014年 clowwindy. All rights reserved.
//
// Changed by QiuYuzhou


#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import "../ShadowsocksX-NG/proxy_conf_helper_version.h"

// A library for parsing command line.
// https://github.com/stephencelis/BRLOptionParser
#import <BRLOptionParser/BRLOptionParser.h>


int main(int argc, const char * argv[])
{
    NSString* mode;
    NSString* pacURL;
    NSString* portString;
    
    BRLOptionParser *options = [BRLOptionParser new];
    [options setBanner:@"Usage: %s [-v] [-m auto|global|off] [-u <url>] [-p <port>]", argv[0]];
    
    // Version
    [options addOption:"version" flag:'v' description:@"Print the version number." block:^{
        printf("%s", [kProxyConfHelperVersion UTF8String]);
        exit(EXIT_SUCCESS);
    }];
    
    // Help
    __weak typeof(options) weakOptions = options;
    [options addOption:"help" flag:'h' description:@"Show this message" block:^{
        printf("%s", [[weakOptions description] UTF8String]);
        exit(EXIT_SUCCESS);
    }];
    
    // Mode
    [options addOption:"mode" flag:'m' description:@"Proxy mode, may be: auto,blobal,off" argument:&mode];
    
    [options addOption:"pac-url" flag:'u' description:@"PAC file url for auto mode." argument:&pacURL];
    [options addOption:"port" flag:'p' description:@"Listen port for global mode." argument:&portString];
    
    NSMutableSet* networkServiceKeys = [NSMutableSet set];
    [options addOption:"network-service" flag:'n' description:@"Manual specify the network profile need to set proxy." blockWithArgument:^(NSString* value){
        [networkServiceKeys addObject:value];
    }];
    
    NSError *error = nil;
    if (![options parseArgc:argc argv:argv error:&error]) {
        const char * message = error.localizedDescription.UTF8String;
        fprintf(stderr, "%s: %s\n", argv[0], message);
        exit(EXIT_FAILURE);
    }
    
    NSInteger port = 0;
    if (mode) {
        if ([@"auto" isEqualToString:mode]) {
            if (!pacURL) {
                return 1;
            }
        } else if ([@"global" isEqualToString:mode]) {
            if (!portString) {
                return 1;
            }
            port = [portString integerValue];
            if (0 == port) {
                return 1;
            }
        } else if (![@"off" isEqualToString:mode]) {
            return 1;
        }
    } else {
        printf("%s", [kProxyConfHelperVersion UTF8String]);
        return 0;
    }
    
    
    static AuthorizationRef authRef;
    static AuthorizationFlags authFlags;
    authFlags = kAuthorizationFlagDefaults
    | kAuthorizationFlagExtendRights
    | kAuthorizationFlagInteractionAllowed
    | kAuthorizationFlagPreAuthorize;
    OSStatus authErr = AuthorizationCreate(nil, kAuthorizationEmptyEnvironment, authFlags, &authRef);
    if (authErr != noErr) {
        authRef = nil;
        NSLog(@"Error when create authorization");
        return 1;
    } else {
        if (authRef == NULL) {
            NSLog(@"No authorization has been granted to modify network configuration");
            return 1;
        }
        
        SCPreferencesRef prefRef = SCPreferencesCreateWithAuthorization(nil, CFSTR("Shadowsocks"), nil, authRef);
        
        NSDictionary *sets = (__bridge NSDictionary *)SCPreferencesGetValue(prefRef, kSCPrefNetworkServices);
        
        NSMutableDictionary *proxies = [[NSMutableDictionary alloc] init];
        [proxies setObject:[NSNumber numberWithInt:0] forKey:(NSString *)kCFNetworkProxiesHTTPEnable];
        [proxies setObject:[NSNumber numberWithInt:0] forKey:(NSString *)kCFNetworkProxiesHTTPSEnable];
        [proxies setObject:[NSNumber numberWithInt:0] forKey:(NSString *)kCFNetworkProxiesProxyAutoConfigEnable];
        [proxies setObject:[NSNumber numberWithInt:0] forKey:(NSString *)kCFNetworkProxiesSOCKSEnable];
        [proxies setObject:@[] forKey:(NSString *)kCFNetworkProxiesExceptionsList];
        
        // 遍历系统中的网络设备列表，设置 AirPort 和 Ethernet 的代理
        for (NSString *key in [sets allKeys]) {
            NSMutableDictionary *dict = [sets objectForKey:key];
            NSString *hardware = [dict valueForKeyPath:@"Interface.Hardware"];
            //        NSLog(@"%@", hardware);
            BOOL modify = NO;
            if ([networkServiceKeys count] > 0) {
                if ([networkServiceKeys containsObject:key]) {
                    modify = YES;
                }
            } else if ([hardware isEqualToString:@"AirPort"]
                       || [hardware isEqualToString:@"Wi-Fi"]
                       || [hardware isEqualToString:@"Ethernet"]) {
                modify = YES;
            }
            
            if (modify) {
                
                if ([mode isEqualToString:@"auto"]) {
                    
                    [proxies setObject:pacURL forKey:(NSString *)kCFNetworkProxiesProxyAutoConfigURLString];
                    [proxies setObject:[NSNumber numberWithInt:1] forKey:(NSString *)kCFNetworkProxiesProxyAutoConfigEnable];
                    
                } else if ([mode isEqualToString:@"global"]) {
                    
                    
                    [proxies setObject:@"127.0.0.1" forKey:(NSString *)
                     kCFNetworkProxiesSOCKSProxy];
                    [proxies setObject:[NSNumber numberWithInteger:port] forKey:(NSString*)
                     kCFNetworkProxiesSOCKSPort];
                    [proxies setObject:[NSNumber numberWithInt:1] forKey:(NSString*)
                     kCFNetworkProxiesSOCKSEnable];
                    [proxies setObject:@[@"127.0.0.1", @"localhost"] forKey:(NSString *)kCFNetworkProxiesExceptionsList];
                    
                }
                
                SCPreferencesPathSetValue(prefRef, (__bridge CFStringRef)[NSString stringWithFormat:@"/%@/%@/%@", kSCPrefNetworkServices, key, kSCEntNetProxies], (__bridge CFDictionaryRef)proxies);
            }
        }
        
        SCPreferencesCommitChanges(prefRef);
        SCPreferencesApplyChanges(prefRef);
        SCPreferencesSynchronize(prefRef);
        
        AuthorizationFree(authRef, kAuthorizationFlagDefaults);
    }
    
    printf("pac proxy set to %s", [mode UTF8String]);
    
    return 0;
}
