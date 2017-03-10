//
//  ShortcutsController.m
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 2017/3/10.
//  Copyright © 2017年 qiuyuzhou. All rights reserved.
//

#import "ShortcutsController.h"

#import <MASShortcut/Shortcut.h>

#import "ShortcutsPreferencesWindowController.h"


@implementation ShortcutsController

+ (void)bindShortcuts {
    MASShortcutBinder* binder = [MASShortcutBinder sharedBinder];
    [binder
     bindShortcutWithDefaultsKey:kGlobalShortcutToggleRunning
     toAction:^{
         [[NSNotificationCenter defaultCenter] postNotificationName: @"NOTIFY_TOGGLE_RUNNING" object: nil];
     }];    
    [binder
     bindShortcutWithDefaultsKey:kGlobalShortcutSwitchProxyMode
     toAction:^{
         [[NSNotificationCenter defaultCenter] postNotificationName: @"NOTIFY_SWITCH_PROXY_MODE" object: nil];
     }];    
}

@end
