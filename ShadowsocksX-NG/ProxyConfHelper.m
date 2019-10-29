//
//  ProxyConfHelper.m
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/10.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

#import "ProxyConfHelper.h"
#import "proxy_conf_helper_version.h"

#define kShadowsocksHelper @"/Library/Application Support/ShadowsocksX-NG/proxy_conf_helper"

@implementation ProxyConfHelper

GCDWebServer *webServer = nil;

+ (BOOL)isVersionOk {
    NSTask *task;
    task = [[NSTask alloc] init];
    [task setLaunchPath:kShadowsocksHelper];
    
    NSArray *args;
    args = [NSArray arrayWithObjects:@"-v", nil];
    [task setArguments: args];
    
    NSPipe *pipe;
    pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    
    NSFileHandle *fd;
    fd = [pipe fileHandleForReading];
    
    [task launch];
    
    NSData *data;
    data = [fd readDataToEndOfFile];
    
    NSString *str;
    str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    if (![str isGreaterThanOrEqualTo: kProxyConfHelperVersion]) {
        return NO;
    }
    return YES;
}

+ (void)install {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:kShadowsocksHelper] || ![self isVersionOk]) {
        NSString *helperPath = [NSString stringWithFormat:@"%@/%@", [[NSBundle mainBundle] resourcePath], @"install_helper.sh"];
        NSLog(@"run install script: %@", helperPath);
        NSDictionary *error;
        NSString *script = [NSString stringWithFormat:@"do shell script \"/bin/bash \\\"%@\\\"\" with administrator privileges", helperPath];
        NSAppleScript *appleScript = [[NSAppleScript new] initWithSource:script];
        if ([appleScript executeAndReturnError:&error]) {
            NSLog(@"installation success");
        } else {
            NSLog(@"installation failure: %@", error);
        }
    }
}

+ (void)callHelper:(NSArray*) arguments {
    NSTask *task;
    task = [[NSTask alloc] init];
    [task setLaunchPath:kShadowsocksHelper];

    // this log is very important
    NSLog(@"run shadowsocks helper: %@", kShadowsocksHelper);
    [task setArguments:arguments];

    NSPipe *stdoutpipe;
    stdoutpipe = [NSPipe pipe];
    [task setStandardOutput:stdoutpipe];

    NSPipe *stderrpipe;
    stderrpipe = [NSPipe pipe];
    [task setStandardError:stderrpipe];

    NSFileHandle *file;
    file = [stdoutpipe fileHandleForReading];

    [task launch];

    NSData *data;
    data = [file readDataToEndOfFile];

    NSString *string;
    string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (string.length > 0) {
        NSLog(@"%@", string);
    }

    file = [stderrpipe fileHandleForReading];
    data = [file readDataToEndOfFile];
    string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (string.length > 0) {
        NSLog(@"%@", string);
    }
}

+ (void)addArguments4ManualSpecifyNetworkServices:(NSMutableArray*) args {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    
    if (![defaults boolForKey:@"AutoConfigureNetworkServices"]) {
        NSArray* serviceKeys = [defaults arrayForKey:@"Proxy4NetworkServices"];
        if (serviceKeys) {
            for (NSString* key in serviceKeys) {
                [args addObject:@"--network-service"];
                [args addObject:key];
            }
        }
    }
}

+ (void)addArguments4ManualSpecifyProxyExceptions:(NSMutableArray*) args {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];

    NSString* rawExceptions = [defaults stringForKey:@"ProxyExceptions"];
    if (rawExceptions) {
        NSCharacterSet* whites = [NSCharacterSet whitespaceAndNewlineCharacterSet];
        NSMutableCharacterSet* seps = [NSMutableCharacterSet characterSetWithCharactersInString:@",、"];
        [seps formUnionWithCharacterSet:whites];

        NSArray* exceptions = [rawExceptions componentsSeparatedByCharactersInSet:seps];
        for (NSString* domainOrHost in exceptions) {
            if ([domainOrHost length] > 0) {
                [args addObject:@"-x"];
                [args addObject:domainOrHost];
            }
        }
    }
}

+ (NSString*)getPACFilePath {
    return [NSString stringWithFormat:@"%@/%@", NSHomeDirectory(), @".ShadowsocksX-NG/gfwlist.js"];
}

+ (void)enablePACProxy {
    //start server here and then using the string next line
    //next two lines can open gcdwebserver and work around pac file
    NSString* PACFilePath = [self getPACFilePath];
    [self startPACServer: PACFilePath];
    
    NSURL* url = [NSURL URLWithString: [self getHttpPACUrl]];
    
    NSMutableArray* args = [@[@"--mode", @"auto", @"--pac-url", [url absoluteString]]mutableCopy];
    
    [self addArguments4ManualSpecifyNetworkServices:args];
    [self addArguments4ManualSpecifyProxyExceptions:args];
    [self callHelper:args];
}

+ (void)enableGlobalProxy {
    NSString* socks5ListenAddress = [[NSUserDefaults standardUserDefaults]stringForKey:@"LocalSocks5.ListenAddress"];
    NSUInteger port = [[NSUserDefaults standardUserDefaults]integerForKey:@"LocalSocks5.ListenPort"];
    
    NSMutableArray* args = [@[@"--mode", @"global", @"--port"
                              , [NSString stringWithFormat:@"%lu", (unsigned long)port],@"--socks-listen-address",socks5ListenAddress]mutableCopy];
    
    // Known issue #106 https://github.com/shadowsocks/ShadowsocksX-NG/issues/106
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"LocalHTTPOn"] && [[NSUserDefaults standardUserDefaults] boolForKey:@"LocalHTTP.FollowGlobal"]) {
        NSUInteger privoxyPort = [[NSUserDefaults standardUserDefaults]integerForKey:@"LocalHTTP.ListenPort"];
        NSString* privoxyListenAddress = [[NSUserDefaults standardUserDefaults]stringForKey:@"LocalHTTP.ListenAddress"];
        [args addObject:@"--privoxy-port"];
        [args addObject:[NSString stringWithFormat:@"%lu", (unsigned long)privoxyPort]];
        [args addObject:@"--privoxy-listen-address"];
        [args addObject:privoxyListenAddress];
    }
    
    [self addArguments4ManualSpecifyNetworkServices:args];
    [self addArguments4ManualSpecifyProxyExceptions:args];
    [self callHelper:args];
    [self stopPACServer];
}

+ (void)disableProxy {
    // 带上所有参数是为了判断是否原有代理设置是否由ssx-ng设置的。如果是用户手工设置的其他配置，则不进行清空。
    NSURL* url = [NSURL URLWithString: [self getHttpPACUrl]];
    NSString* socks5ListenAddress = [[NSUserDefaults standardUserDefaults]stringForKey:@"LocalSocks5.ListenAddress"];
    NSUInteger port = [[NSUserDefaults standardUserDefaults]integerForKey:@"LocalSocks5.ListenPort"];
    
    NSMutableArray* args = [@[@"--mode", @"off"
                              , @"--pac-url", [url absoluteString]
                              , @"--port", [NSString stringWithFormat:@"%lu", (unsigned long)port]
                              , @"--socks-listen-address",socks5ListenAddress
                              ]mutableCopy];
    [self addArguments4ManualSpecifyNetworkServices:args];
    [self addArguments4ManualSpecifyProxyExceptions:args];
    [self callHelper:args];
    [self stopPACServer];
}

+ (void)enableExternalPACProxy {
    NSURL* url = [NSURL URLWithString: [self getExternalPACUrl]];
    NSMutableArray* args = [@[@"--mode", @"auto"
                              , @"--pac-url", [url absoluteString]
                              ]mutableCopy];
    [self addArguments4ManualSpecifyNetworkServices:args];
    [self addArguments4ManualSpecifyProxyExceptions:args];
    [self callHelper:args];
    [self stopPACServer];
}

+ (NSString*)getHttpPACUrl {
    NSString * routerPath = @"/proxy.pac";
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSString * address = @"localhost";
    int port = (short)[defaults integerForKey:@"PacServer.ListenPort"];
    
    return [NSString stringWithFormat:@"%@%@:%d%@",@"http://",address,port,routerPath];
}

+ (NSString*)getExternalPACUrl {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    return [defaults stringForKey:@"ExternalPACURL"];
}

+ (void)startPACServer:(NSString*) PACFilePath {
    [self stopPACServer];
    
    NSString * routerPath = @"/proxy.pac";
    
    NSData* originalPACData = [NSData dataWithContentsOfFile:PACFilePath];
    
    webServer = [[GCDWebServer alloc] init];
    

    [webServer addHandlerForMethod:@"GET"
                              path:routerPath
                      requestClass:[GCDWebServerRequest class]
                      processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request)
    {
        GCDWebServerDataResponse* resp = [GCDWebServerDataResponse responseWithData:originalPACData
                                                                        contentType:@"application/x-ns-proxy-autoconfig"];
        return resp;
    }
     ];
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    BOOL bindToLocalhost = [defaults boolForKey:@"PacServer.BindToLocalhost"];
    int port = (short)[defaults integerForKey:@"PacServer.ListenPort"];
    
    [webServer startWithOptions:@{
        GCDWebServerOption_BindToLocalhost: @(bindToLocalhost),
        GCDWebServerOption_Port: @(port)
    } error:nil];
}

+ (void)stopPACServer {
    //原版似乎没有处理这个，本来设计计划如果切换到全局模式或者手动模式就关掉webserver 似乎没有这个必要了？
    if ([webServer isRunning]) {
        [webServer stop];
    }
}

+ (void)startMonitorPAC {
    // Monitor change event of the PAC file.
    NSString* PACFilePath = [self getPACFilePath];
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    int fileId = open([PACFilePath UTF8String], O_EVTONLY);
    __block dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fileId,
                                                              DISPATCH_VNODE_DELETE | DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_ATTRIB | DISPATCH_VNODE_LINK | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_REVOKE,
                                                              queue);
    dispatch_source_set_event_handler(source, ^
                                      {
                                          unsigned long flags = dispatch_source_get_data(source);
                                          if(flags & DISPATCH_VNODE_DELETE)
                                          {
                                              dispatch_source_cancel(source);
                                          }
                                          
                                          // The PAC file was written by atomically (PACUtils.swift:134)
                                          // That means DISPATCH_VNODE_DELETE event always be trigged
                                          // Need to be run the following statements in any events
                                          NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
                                          if ([defaults boolForKey:@"ShadowsocksOn"]) {
                                              if ([[defaults stringForKey:@"ShadowsocksRunningMode"] isEqualToString:@"auto"]) {
                                                  [ProxyConfHelper disableProxy];
                                                  [ProxyConfHelper enablePACProxy];
                                              }
                                          }
                                      });
    dispatch_source_set_cancel_handler(source, ^(void) 
                                       {
                                           close(fileId);
                                       });
    dispatch_resume(source);
}

@end
