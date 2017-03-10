//
//  ShortcutsPreferencesWindowController.m
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 2017/3/10.
//  Copyright © 2017年 qiuyuzhou. All rights reserved.
//

#import "ShortcutsPreferencesWindowController.h"


@interface ShortcutsPreferencesWindowController ()

@end

@implementation ShortcutsPreferencesWindowController

- (void)windowDidLoad {
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    self.toggleRunningShortcutCtrl.associatedUserDefaultsKey = kGlobalShortcutToggleRunning;
    self.switchModeShortcutCtrl.associatedUserDefaultsKey = kGlobalShortcutSwitchProxyMode;
}

@end
