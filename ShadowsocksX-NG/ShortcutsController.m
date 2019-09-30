//
//  ShortcutsController.m
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 2017/3/10.
//  Copyright © 2017年 qiuyuzhou. All rights reserved.
//

#import "ShortcutsController.h"

#import <MASShortcut/Shortcut.h>


@implementation ShortcutsController

+ (void)bindShortcuts {
    MASShortcutBinder* binder = [MASShortcutBinder sharedBinder];
    [binder
     bindShortcutWithDefaultsKey: @"ToggleRunning"
     toAction:^{
         [[NSNotificationCenter defaultCenter] postNotificationName: @"NOTIFY_TOGGLE_RUNNING_SHORTCUT" object: nil];
     }];    
    [binder
     bindShortcutWithDefaultsKey: @"SwitchProxyMode"
     toAction:^{
         [[NSNotificationCenter defaultCenter] postNotificationName: @"NOTIFY_SWITCH_PROXY_MODE_SHORTCUT" object: nil];
     }];    
}

@end
