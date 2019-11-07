#import "MASShortcutValidator.h"
#import "MASLocalization.h"

@implementation MASShortcutValidator

+ (instancetype) sharedValidator
{
    static dispatch_once_t once;
    static MASShortcutValidator *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (BOOL) isShortcutValid: (MASShortcut*) shortcut
{
    NSInteger keyCode = [shortcut keyCode];
    NSEventModifierFlags modifiers = [shortcut modifierFlags];

    // Allow any function key with any combination of modifiers
    BOOL includesFunctionKey = ((keyCode == kVK_F1) || (keyCode == kVK_F2) || (keyCode == kVK_F3) || (keyCode == kVK_F4) ||
                                (keyCode == kVK_F5) || (keyCode == kVK_F6) || (keyCode == kVK_F7) || (keyCode == kVK_F8) ||
                                (keyCode == kVK_F9) || (keyCode == kVK_F10) || (keyCode == kVK_F11) || (keyCode == kVK_F12) ||
                                (keyCode == kVK_F13) || (keyCode == kVK_F14) || (keyCode == kVK_F15) || (keyCode == kVK_F16) ||
                                (keyCode == kVK_F17) || (keyCode == kVK_F18) || (keyCode == kVK_F19) || (keyCode == kVK_F20));
    if (includesFunctionKey) return YES;

    // Do not allow any other key without modifiers
    BOOL hasModifierFlags = (modifiers > 0);
    if (!hasModifierFlags) return NO;

    // Allow any hotkey containing Control or Command modifier
    BOOL includesCommand = ((modifiers & NSCommandKeyMask) > 0);
    BOOL includesControl = ((modifiers & NSControlKeyMask) > 0);
    if (includesCommand || includesControl) return YES;

    // Allow Option key only in selected cases
    BOOL includesOption = ((modifiers & NSAlternateKeyMask) > 0);
    if (includesOption) {

        // Always allow Option-Space and Option-Escape because they do not have any bind system commands
        if ((keyCode == kVK_Space) || (keyCode == kVK_Escape)) return YES;

        // Allow Option modifier with any key even if it will break the system binding
        if (_allowAnyShortcutWithOptionModifier) return YES;
    }

    // The hotkey does not have any modifiers or violates system bindings
    return NO;
}

- (BOOL) isShortcut: (MASShortcut*) shortcut alreadyTakenInMenu: (NSMenu*) menu explanation: (NSString**) explanation
{
    NSString *keyEquivalent = [shortcut keyCodeStringForKeyEquivalent];
    NSEventModifierFlags flags = [shortcut modifierFlags];

    for (NSMenuItem *menuItem in menu.itemArray) {
        if (menuItem.hasSubmenu && [self isShortcut:shortcut alreadyTakenInMenu:[menuItem submenu] explanation:explanation]) return YES;
        
        BOOL equalFlags = (MASPickCocoaModifiers(menuItem.keyEquivalentModifierMask) == flags);
        BOOL equalHotkeyLowercase = [menuItem.keyEquivalent.lowercaseString isEqualToString:keyEquivalent];
        
        // Check if the cases are different, we know ours is lower and that shift is included in our modifiers
        // If theirs is capitol, we need to add shift to their modifiers
        if (equalHotkeyLowercase && ![menuItem.keyEquivalent isEqualToString:keyEquivalent]) {
            equalFlags = (MASPickCocoaModifiers(menuItem.keyEquivalentModifierMask | NSShiftKeyMask) == flags);
        }
        
        if (equalFlags && equalHotkeyLowercase) {
            if (explanation) {
                *explanation = MASLocalizedString(@"This shortcut cannot be used because it is already used by the menu item ‘%@’.",
                                                     @"Message for alert when shortcut is already used");
                *explanation = [NSString stringWithFormat:*explanation, menuItem.title];
            }
            return YES;
        }
    }
    return NO;
}

- (BOOL) isShortcutAlreadyTakenBySystem: (MASShortcut*) shortcut explanation: (NSString**) explanation
{
    CFArrayRef globalHotKeys;
    if (CopySymbolicHotKeys(&globalHotKeys) == noErr) {

        // Enumerate all global hotkeys and check if any of them matches current shortcut
        for (CFIndex i = 0, count = CFArrayGetCount(globalHotKeys); i < count; i++) {
            CFDictionaryRef hotKeyInfo = CFArrayGetValueAtIndex(globalHotKeys, i);
            CFNumberRef code = CFDictionaryGetValue(hotKeyInfo, kHISymbolicHotKeyCode);
            CFNumberRef flags = CFDictionaryGetValue(hotKeyInfo, kHISymbolicHotKeyModifiers);
            CFNumberRef enabled = CFDictionaryGetValue(hotKeyInfo, kHISymbolicHotKeyEnabled);

            if (([(__bridge NSNumber *)code integerValue] == [shortcut keyCode]) &&
                ([(__bridge NSNumber *)flags unsignedIntegerValue] == [shortcut carbonFlags]) &&
                ([(__bridge NSNumber *)enabled boolValue])) {

                if (explanation) {
                    *explanation = MASLocalizedString(@"This combination cannot be used because it is already used by a system-wide "
                                                     @"keyboard shortcut.\nIf you really want to use this key combination, most shortcuts "
                                                     @"can be changed in the Keyboard & Mouse panel in System Preferences.",
                                                     @"Message for alert when shortcut is already used by the system");
                }
                return YES;
            }
        }
        CFRelease(globalHotKeys);
    }
    return [self isShortcut:shortcut alreadyTakenInMenu:[NSApp mainMenu] explanation:explanation];
}

@end
