#import "MASShortcut.h"
#import "MASLocalization.h"

static NSString *const MASShortcutKeyCode = @"KeyCode";
static NSString *const MASShortcutModifierFlags = @"ModifierFlags";

@implementation MASShortcut

#pragma mark Initialization

- (instancetype)initWithKeyCode:(NSInteger)code modifierFlags:(NSEventModifierFlags)flags
{
    self = [super init];
    if (self) {
        _keyCode = code;
        _modifierFlags = MASPickCocoaModifiers(flags);
    }
    return self;
}

+ (instancetype)shortcutWithKeyCode:(NSInteger)code modifierFlags:(NSEventModifierFlags)flags
{
    return [[self alloc] initWithKeyCode:code modifierFlags:flags];
}

+ (instancetype)shortcutWithEvent:(NSEvent *)event
{
    return [[self alloc] initWithKeyCode:event.keyCode modifierFlags:event.modifierFlags];
}

#pragma mark Shortcut Accessors

- (UInt32)carbonKeyCode
{
    return (self.keyCode == NSNotFound ? 0 : (UInt32)self.keyCode);
}

- (UInt32)carbonFlags
{
    return MASCarbonModifiersFromCocoaModifiers(self.modifierFlags);
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@%@", self.modifierFlagsString, self.keyCodeString];
}

- (NSString *)keyCodeStringForKeyEquivalent
{
    NSString *keyCodeString = self.keyCodeString;

    if (keyCodeString.length <= 1) {
        return keyCodeString.lowercaseString;
    }

    switch (self.keyCode) {
        case kVK_F1: return NSStringFromMASKeyCode(NSF1FunctionKey);
        case kVK_F2: return NSStringFromMASKeyCode(NSF2FunctionKey);
        case kVK_F3: return NSStringFromMASKeyCode(NSF3FunctionKey);
        case kVK_F4: return NSStringFromMASKeyCode(NSF4FunctionKey);
        case kVK_F5: return NSStringFromMASKeyCode(NSF5FunctionKey);
        case kVK_F6: return NSStringFromMASKeyCode(NSF6FunctionKey);
        case kVK_F7: return NSStringFromMASKeyCode(NSF7FunctionKey);
        case kVK_F8: return NSStringFromMASKeyCode(NSF8FunctionKey);
        case kVK_F9: return NSStringFromMASKeyCode(NSF9FunctionKey);
        case kVK_F10: return NSStringFromMASKeyCode(NSF10FunctionKey);
        case kVK_F11: return NSStringFromMASKeyCode(NSF11FunctionKey);
        case kVK_F12: return NSStringFromMASKeyCode(NSF12FunctionKey);
        case kVK_F13: return NSStringFromMASKeyCode(NSF13FunctionKey);
        case kVK_F14: return NSStringFromMASKeyCode(NSF14FunctionKey);
        case kVK_F15: return NSStringFromMASKeyCode(NSF15FunctionKey);
        case kVK_F16: return NSStringFromMASKeyCode(NSF16FunctionKey);
        case kVK_F17: return NSStringFromMASKeyCode(NSF17FunctionKey);
        case kVK_F18: return NSStringFromMASKeyCode(NSF18FunctionKey);
        case kVK_F19: return NSStringFromMASKeyCode(NSF19FunctionKey);
        case kVK_Space: return NSStringFromMASKeyCode(0x20);
        default: return @"";
    }
}

- (NSString *)keyCodeString
{
    // Some key codes don't have an equivalent
    switch (self.keyCode) {
        case NSNotFound: return @"";
        case kVK_F1: return @"F1";
        case kVK_F2: return @"F2";
        case kVK_F3: return @"F3";
        case kVK_F4: return @"F4";
        case kVK_F5: return @"F5";
        case kVK_F6: return @"F6";
        case kVK_F7: return @"F7";
        case kVK_F8: return @"F8";
        case kVK_F9: return @"F9";
        case kVK_F10: return @"F10";
        case kVK_F11: return @"F11";
        case kVK_F12: return @"F12";
        case kVK_F13: return @"F13";
        case kVK_F14: return @"F14";
        case kVK_F15: return @"F15";
        case kVK_F16: return @"F16";
        case kVK_F17: return @"F17";
        case kVK_F18: return @"F18";
        case kVK_F19: return @"F19";
        case kVK_Space: return MASLocalizedString(@"Space", @"Shortcut glyph name for SPACE key");
        case kVK_Escape: return NSStringFromMASKeyCode(kMASShortcutGlyphEscape);
        case kVK_Delete: return NSStringFromMASKeyCode(kMASShortcutGlyphDeleteLeft);
        case kVK_ForwardDelete: return NSStringFromMASKeyCode(kMASShortcutGlyphDeleteRight);
        case kVK_LeftArrow: return NSStringFromMASKeyCode(kMASShortcutGlyphLeftArrow);
        case kVK_RightArrow: return NSStringFromMASKeyCode(kMASShortcutGlyphRightArrow);
        case kVK_UpArrow: return NSStringFromMASKeyCode(kMASShortcutGlyphUpArrow);
        case kVK_DownArrow: return NSStringFromMASKeyCode(kMASShortcutGlyphDownArrow);
        case kVK_Help: return NSStringFromMASKeyCode(kMASShortcutGlyphHelp);
        case kVK_PageUp: return NSStringFromMASKeyCode(kMASShortcutGlyphPageUp);
        case kVK_PageDown: return NSStringFromMASKeyCode(kMASShortcutGlyphPageDown);
        case kVK_Tab: return NSStringFromMASKeyCode(kMASShortcutGlyphTabRight);
        case kVK_Return: return NSStringFromMASKeyCode(kMASShortcutGlyphReturnR2L);
            
        // Keypad
        case kVK_ANSI_Keypad0: return @"0";
        case kVK_ANSI_Keypad1: return @"1";
        case kVK_ANSI_Keypad2: return @"2";
        case kVK_ANSI_Keypad3: return @"3";
        case kVK_ANSI_Keypad4: return @"4";
        case kVK_ANSI_Keypad5: return @"5";
        case kVK_ANSI_Keypad6: return @"6";
        case kVK_ANSI_Keypad7: return @"7";
        case kVK_ANSI_Keypad8: return @"8";
        case kVK_ANSI_Keypad9: return @"9";
        case kVK_ANSI_KeypadDecimal: return @".";
        case kVK_ANSI_KeypadMultiply: return @"*";
        case kVK_ANSI_KeypadPlus: return @"+";
        case kVK_ANSI_KeypadClear: return NSStringFromMASKeyCode(kMASShortcutGlyphPadClear);
        case kVK_ANSI_KeypadDivide: return @"/";
        case kVK_ANSI_KeypadEnter: return NSStringFromMASKeyCode(kMASShortcutGlyphReturn);
        case kVK_ANSI_KeypadMinus: return @"-";
        case kVK_ANSI_KeypadEquals: return @"=";
            
        // Hardcode
        case 119: return NSStringFromMASKeyCode(kMASShortcutGlyphSoutheastArrow);
        case 115: return NSStringFromMASKeyCode(kMASShortcutGlyphNorthwestArrow);
    }
    
    // Everything else should be printable so look it up in the current ASCII capable keyboard layout
    OSStatus error = noErr;
    NSString *keystroke = nil;
    TISInputSourceRef inputSource = TISCopyCurrentASCIICapableKeyboardLayoutInputSource();
    if (inputSource) {
        CFDataRef layoutDataRef = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData);
        if (layoutDataRef) {
            UCKeyboardLayout *layoutData = (UCKeyboardLayout *)CFDataGetBytePtr(layoutDataRef);
            UniCharCount length = 0;
            UniChar  chars[256] = { 0 };
            UInt32 deadKeyState = 0;
            error = UCKeyTranslate(layoutData, (UInt16)self.keyCode, kUCKeyActionDisplay, 0, // No modifiers
                                   LMGetKbdType(), kUCKeyTranslateNoDeadKeysMask, &deadKeyState,
                                   sizeof(chars) / sizeof(UniChar), &length, chars);
            keystroke = ((error == noErr) && length ? [NSString stringWithCharacters:chars length:length] : @"");
        }
        CFRelease(inputSource);
    }
    
    // Validate keystroke
    if (keystroke.length) {
        static NSMutableCharacterSet *validChars = nil;
        if (validChars == nil) {
            validChars = [[NSMutableCharacterSet alloc] init];
            [validChars formUnionWithCharacterSet:[NSCharacterSet alphanumericCharacterSet]];
            [validChars formUnionWithCharacterSet:[NSCharacterSet punctuationCharacterSet]];
            [validChars formUnionWithCharacterSet:[NSCharacterSet symbolCharacterSet]];
        }
        for (NSUInteger i = 0, length = keystroke.length; i < length; i++) {
            if (![validChars characterIsMember:[keystroke characterAtIndex:i]]) {
                keystroke = @"";
                break;
            }
        }
    }
    
    // Finally, we've got a shortcut!
    return keystroke.uppercaseString;
}

- (NSString *)modifierFlagsString
{
    unichar chars[4];
    NSUInteger count = 0;
    // These are in the same order as the menu manager shows them
    if (self.modifierFlags & NSControlKeyMask) chars[count++] = kControlUnicode;
    if (self.modifierFlags & NSAlternateKeyMask) chars[count++] = kOptionUnicode;
    if (self.modifierFlags & NSShiftKeyMask) chars[count++] = kShiftUnicode;
    if (self.modifierFlags & NSCommandKeyMask) chars[count++] = kCommandUnicode;
    return (count ? [NSString stringWithCharacters:chars length:count] : @"");
}

#pragma mark NSObject

- (BOOL) isEqual: (MASShortcut*) object
{
    return [object isKindOfClass:[self class]]
        && (object.keyCode == self.keyCode)
        && (object.modifierFlags == self.modifierFlags);
}

- (NSUInteger) hash
{
    return self.keyCode + self.modifierFlags;
}

#pragma mark NSCoding

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInteger:(self.keyCode != NSNotFound ? self.keyCode : - 1) forKey:MASShortcutKeyCode];
    [coder encodeInteger:(NSInteger)self.modifierFlags forKey:MASShortcutModifierFlags];
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    self = [super init];
    if (self) {
        NSInteger code = [decoder decodeIntegerForKey:MASShortcutKeyCode];
        _keyCode = (code < 0) ? NSNotFound : code;
        _modifierFlags = [decoder decodeIntegerForKey:MASShortcutModifierFlags];
    }
    return self;
}

#pragma mark NSSecureCoding

+ (BOOL)supportsSecureCoding
{
    return YES;
}

#pragma mark NSCopying

- (instancetype) copyWithZone:(NSZone *)zone
{
    return [[self class] shortcutWithKeyCode:_keyCode modifierFlags:_modifierFlags];
}

@end
