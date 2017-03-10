//
//  ShortcutsPreferencesWindowController.h
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 2017/3/10.
//  Copyright © 2017年 qiuyuzhou. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <MASShortcut/Shortcut.h>


static NSString *const kGlobalShortcutToggleRunning = @"ToggleRunning";
static NSString *const kGlobalShortcutSwitchProxyMode= @"SwitchProxyMode";


@interface ShortcutsPreferencesWindowController : NSWindowController

@property(nonatomic, weak) IBOutlet MASShortcutView* toggleRunningShortcutCtrl;
@property(nonatomic, weak) IBOutlet MASShortcutView* switchModeShortcutCtrl;

@end
