#import "MASLocalization.h"
#import "MASShortcut.h"

static NSString *const MASLocalizationTableName = @"Localizable";
static NSString *const MASPlaceholderLocalizationString = @"XXX";

// The CocoaPods trickery here is needed because when the code
// is built as a part of CocoaPods, it won’t make a separate framework
// and the Localized.strings file won’t be bundled correctly.
// See https://github.com/shpakovski/MASShortcut/issues/74
NSString *MASLocalizedString(NSString *key, NSString *comment) {
    static NSBundle *localizationBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *frameworkBundle = [NSBundle bundleForClass:[MASShortcut class]];
        // first we'll check if resources bundle was copied to MASShortcut framework bundle when !use_frameworks option is active
        NSURL *cocoaPodsBundleURL = [frameworkBundle URLForResource:@"MASShortcut" withExtension:@"bundle"];
        if (cocoaPodsBundleURL) {
            localizationBundle = [NSBundle bundleWithURL: cocoaPodsBundleURL];
        } else {
            // trying to fetch cocoapods bundle from main bundle
            cocoaPodsBundleURL = [[NSBundle mainBundle] URLForResource: @"MASShortcut" withExtension:@"bundle"];
            if (cocoaPodsBundleURL) {
                localizationBundle = [NSBundle bundleWithURL: cocoaPodsBundleURL];
            } else {
                // fallback to framework bundle
                localizationBundle = frameworkBundle;
            }
        }
    });
    return [localizationBundle localizedStringForKey:key
        value:MASPlaceholderLocalizationString
        table:MASLocalizationTableName];
}
