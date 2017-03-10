/**
 Reads a localized string from the framework’s bundle.

 Normally you would use NSLocalizedString to read the localized
 strings, but that’s just a shortcut for loading the strings from
 the main bundle. And once the framework ends up in an app, the
 main bundle will be the app’s bundle and won’t contain our strings.
 So we introduced this helper function that makes sure to load the
 strings from the framework’s bundle. Please avoid using
 NSLocalizedString throughout the framework, it wouldn’t work
 properly.
*/
NSString *MASLocalizedString(NSString *key, NSString *comment);