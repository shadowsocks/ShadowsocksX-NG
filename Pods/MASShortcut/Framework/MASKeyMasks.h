#import <Availability.h>

// https://github.com/shpakovski/MASShortcut/issues/99
//
// Long story short: NSControlKeyMask and friends were replaced with NSEventModifierFlagControl
// and similar in macOS Sierra. The project builds fine & clean, but including MASShortcut in
// a project with deployment target set to 10.12 results in several deprecation warnings because
// of the control masks. Simply replacing the old symbols with the new ones isn’t an option,
// since it breaks the build on older SDKs – in Travis, for example.
//
// It should be safe to remove this whole thing once the 10.12 SDK is ubiquitous.

#if __MAC_OS_X_VERSION_MAX_ALLOWED < 101200
#define NSEventModifierFlagCommand  NSCommandKeyMask
#define NSEventModifierFlagControl  NSControlKeyMask
#define NSEventModifierFlagOption   NSAlternateKeyMask
#define NSEventModifierFlagShift    NSShiftKeyMask
#endif
