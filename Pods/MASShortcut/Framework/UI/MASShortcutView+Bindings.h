#import "MASShortcutView.h"

/**
 A simplified interface to bind the recorder value to user defaults.

 You can bind the `shortcutValue` to user defaults using the standard
 `bind:toObject:withKeyPath:options:` call, but since that’s a lot to type
 and read, here’s a simpler option.

 Setting the `associatedUserDefaultsKey` binds the view’s shortcut value
 to the given user defaults key. You can supply a value transformer to convert
 values between user defaults and `MASShortcut`. If you don’t supply
 a transformer, the `NSUnarchiveFromDataTransformerName` will be used
 automatically.

 Set `associatedUserDefaultsKey` to `nil` to disconnect the binding.
*/
@interface MASShortcutView (Bindings)

@property(copy) NSString *associatedUserDefaultsKey;

- (void) setAssociatedUserDefaultsKey: (NSString*) newKey withTransformer: (NSValueTransformer*) transformer;
- (void) setAssociatedUserDefaultsKey: (NSString*) newKey withTransformerName: (NSString*) transformerName;

@end
