//
//  LaunchAtLoginController.m
//
//  Copyright 2011 Tomáš Znamenáček
//  Copyright 2010 Ben Clark-Robinson
//
//  Permission is hereby granted, free of charge, to any person obtaining
//  a copy of this software and associated documentation files (the ‘Software’),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED ‘AS IS’, WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
//  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
//  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
//  CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
//  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
//  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#import "LaunchAtLoginController.h"
#import <ServiceManagement/SMLoginItem.h>

//static NSString *const StartAtLoginKey = @"launchAtLogin";

@interface LaunchAtLoginController () {
    BOOL _enabled;
}

@end

@implementation LaunchAtLoginController

#pragma mark Change Observing


#pragma mark Initialization

- (id) init
{
    self = [super init];
    if (self) {
        _enabled = [[NSUserDefaults standardUserDefaults] boolForKey: @"LaunchAtLogin"];
    }
    return self;
}

- (void) dealloc
{
}

- (void) setLaunchAtLogin: (BOOL) enabled
{
    if (SMLoginItemSetEnabled(
                              (__bridge CFStringRef)@"com.qiuyuzhou.ShadowsocksX-NG.LaunchHelper"
                              , enabled)) {
        _enabled = enabled;
        NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
        [defaults setBool: enabled forKey: @"LaunchAtLogin"];
    }
}

- (BOOL) launchAtLogin
{
    return _enabled;
}

@end
