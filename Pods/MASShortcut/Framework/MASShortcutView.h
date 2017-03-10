@class MASShortcut, MASShortcutValidator;

extern NSString *const MASShortcutBinding;

typedef enum {
    MASShortcutViewStyleDefault = 0,  // Height = 19 px
    MASShortcutViewStyleTexturedRect, // Height = 25 px
    MASShortcutViewStyleRounded,      // Height = 43 px
    MASShortcutViewStyleFlat
} MASShortcutViewStyle;

@interface MASShortcutView : NSView

@property (nonatomic, strong) MASShortcut *shortcutValue;
@property (nonatomic, strong) MASShortcutValidator *shortcutValidator;
@property (nonatomic, getter = isRecording) BOOL recording;
@property (nonatomic, getter = isEnabled) BOOL enabled;
@property (nonatomic, copy) void (^shortcutValueChange)(MASShortcutView *sender);
@property (nonatomic, assign) MASShortcutViewStyle style;

/// Returns custom class for drawing control.
+ (Class)shortcutCellClass;

- (void)setAcceptsFirstResponder:(BOOL)value;

@end
