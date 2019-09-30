#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "MASKeyCodes.h"
#import "MASKeyMasks.h"
#import "MASShortcut.h"
#import "MASShortcutValidator.h"
#import "MASHotKey.h"
#import "MASShortcutMonitor.h"
#import "Shortcut.h"
#import "MASLocalization.h"
#import "MASShortcutView+Bindings.h"
#import "MASShortcutView.h"
#import "MASDictionaryTransformer.h"
#import "MASShortcutBinder.h"

FOUNDATION_EXPORT double MASShortcutVersionNumber;
FOUNDATION_EXPORT const unsigned char MASShortcutVersionString[];

