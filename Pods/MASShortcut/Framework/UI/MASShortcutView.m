#import "MASShortcutView.h"
#import "MASShortcutValidator.h"
#import "MASLocalization.h"

NSString *const MASShortcutBinding = @"shortcutValue";

static const CGFloat MASHintButtonWidth = 23;
static const CGFloat MASButtonFontSize = 11;

#pragma mark -

@interface MASShortcutView () // Private accessors

@property (nonatomic, getter = isHinting) BOOL hinting;
@property (nonatomic, copy) NSString *shortcutPlaceholder;
@property (nonatomic, assign) BOOL showsDeleteButton;

@end

#pragma mark -

@implementation MASShortcutView {
    NSButtonCell *_shortcutCell;
    NSInteger _shortcutToolTipTag;
    NSInteger _hintToolTipTag;
    NSTrackingArea *_hintArea;
    BOOL _acceptsFirstResponder;
}

#pragma mark -

+ (Class)shortcutCellClass
{
    return [NSButtonCell class];
}

- (id)initWithFrame:(CGRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit
{
    _shortcutCell = [[[self.class shortcutCellClass] alloc] init];
    _shortcutCell.buttonType = NSPushOnPushOffButton;
    _shortcutCell.font = [[NSFontManager sharedFontManager] convertFont:_shortcutCell.font toSize:MASButtonFontSize];
    _shortcutValidator = [MASShortcutValidator sharedValidator];
    _enabled = YES;
    _showsDeleteButton = YES;
    _acceptsFirstResponder = NO;
    [self resetShortcutCellStyle];
}

- (void)dealloc
{
    [self activateEventMonitoring:NO];
    [self activateResignObserver:NO];
}

#pragma mark - Public accessors

- (void)setEnabled:(BOOL)flag
{
    if (_enabled != flag) {
        _enabled = flag;
        [self updateTrackingAreas];
        self.recording = NO;
        [self invalidateIntrinsicContentSize];
        [self setNeedsDisplay:YES];
    }
}

- (void)setStyle:(MASShortcutViewStyle)newStyle
{
    if (_style != newStyle) {
        _style = newStyle;
        [self resetShortcutCellStyle];
        [self invalidateIntrinsicContentSize];
        [self setNeedsDisplay:YES];
    }
}

- (void)resetShortcutCellStyle
{
    switch (_style) {
        case MASShortcutViewStyleDefault: {
            _shortcutCell.bezelStyle = NSRoundRectBezelStyle;
            break;
        }
        case MASShortcutViewStyleTexturedRect: {
            _shortcutCell.bezelStyle = NSTexturedRoundedBezelStyle;
            break;
        }
        case MASShortcutViewStyleRounded: {
            _shortcutCell.bezelStyle = NSRoundedBezelStyle;
            break;
        }
        case MASShortcutViewStyleFlat: {
            self.wantsLayer = YES;
            _shortcutCell.backgroundColor = [NSColor clearColor];
            _shortcutCell.bordered = NO;
            break;
        }
    }
}

- (void)setRecording:(BOOL)flag
{
    // Only one recorder can be active at the moment
    static MASShortcutView *currentRecorder = nil;
    if (flag && (currentRecorder != self)) {
        currentRecorder.recording = NO;
        currentRecorder = flag ? self : nil;
    }
    
    // Only enabled view supports recording
    if (flag && !self.enabled) return;

    // Only care about changes in state
    if (flag == _recording) return;

    _recording = flag;
    self.shortcutPlaceholder = nil;
    [self resetToolTips];
    [self activateEventMonitoring:_recording];
    [self activateResignObserver:_recording];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay:YES];

    // Give VoiceOver users feedback on the result. Requires at least 10.9 to run.
    // We’re silencing the “tautological compare” warning here so that if someone
    // takes the naked source files and compiles them with -Wall, the following
    // NSAccessibilityPriorityKey comparison doesn’t cause a warning. See:
    // https://github.com/shpakovski/MASShortcut/issues/76
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wtautological-compare"
    if (_recording == NO && (&NSAccessibilityPriorityKey != NULL)) {
        NSString* msg = _shortcutValue ?
                         MASLocalizedString(@"Shortcut set", @"VoiceOver: Shortcut set") :
                         MASLocalizedString(@"Shortcut cleared", @"VoiceOver: Shortcut cleared");
        NSDictionary *announcementInfo = @{
            NSAccessibilityAnnouncementKey : msg,
            NSAccessibilityPriorityKey : @(NSAccessibilityPriorityHigh),
        };
        NSAccessibilityPostNotificationWithUserInfo(self, NSAccessibilityAnnouncementRequestedNotification, announcementInfo);
    }
    #pragma clang diagnostic pop
}

- (void)setShortcutValue:(MASShortcut *)shortcutValue
{
    _shortcutValue = shortcutValue;
    [self resetToolTips];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay:YES];
    [self propagateValue:shortcutValue forBinding:MASShortcutBinding];

    if (self.shortcutValueChange) {
        self.shortcutValueChange(self);
    }
}

- (void)setShortcutPlaceholder:(NSString *)shortcutPlaceholder
{
    _shortcutPlaceholder = shortcutPlaceholder.copy;
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay:YES];
}

#pragma mark - Appearance

- (BOOL)allowsVibrancy
{
    return YES;
}

#pragma mark - Drawing

- (BOOL)isFlipped
{
    return YES;
}

- (void)drawInRect:(CGRect)frame withTitle:(NSString *)title alignment:(NSTextAlignment)alignment state:(NSInteger)state
{
    _shortcutCell.title = title;
    _shortcutCell.alignment = alignment;
    _shortcutCell.state = state;
    _shortcutCell.enabled = self.enabled;

    switch (_style) {
        case MASShortcutViewStyleDefault: {
            [_shortcutCell drawWithFrame:frame inView:self];
            break;
        }
        case MASShortcutViewStyleTexturedRect: {
            [_shortcutCell drawWithFrame:CGRectOffset(frame, 0.0, 1.0) inView:self];
            break;
        }
        case MASShortcutViewStyleRounded: {
            [_shortcutCell drawWithFrame:CGRectOffset(frame, 0.0, 1.0) inView:self];
            break;
        }
        case MASShortcutViewStyleFlat: {
            [_shortcutCell drawWithFrame:frame inView:self];
            break;
        }
    }
}

- (void)drawRect:(CGRect)dirtyRect
{
    if (self.shortcutValue) {
        NSString *buttonTitle;
        if (self.recording) {
            buttonTitle = NSStringFromMASKeyCode(kMASShortcutGlyphEscape);
        } else if (self.showsDeleteButton) {
            buttonTitle = NSStringFromMASKeyCode(kMASShortcutGlyphClear);
        }
        if (buttonTitle != nil) {
            [self drawInRect:self.bounds withTitle:buttonTitle alignment:NSRightTextAlignment state:NSOffState];
        }
        CGRect shortcutRect;
        [self getShortcutRect:&shortcutRect hintRect:NULL];
        NSString *title = (self.recording
                           ? (_hinting
                              ? MASLocalizedString(@"Use Old Shortcut", @"Cancel action button for non-empty shortcut in recording state")
                              : (self.shortcutPlaceholder.length > 0
                                 ? self.shortcutPlaceholder
                                 : MASLocalizedString(@"Type New Shortcut", @"Non-empty shortcut button in recording state")))
                           : _shortcutValue ? _shortcutValue.description : @"");
        [self drawInRect:shortcutRect withTitle:title alignment:NSCenterTextAlignment state:self.isRecording ? NSOnState : NSOffState];
    }
    else {
        if (self.recording)
        {
            [self drawInRect:self.bounds withTitle:NSStringFromMASKeyCode(kMASShortcutGlyphEscape) alignment:NSRightTextAlignment state:NSOffState];
            
            CGRect shortcutRect;
            [self getShortcutRect:&shortcutRect hintRect:NULL];
            NSString *title = (_hinting
                               ? MASLocalizedString(@"Cancel", @"Cancel action button in recording state")
                               : (self.shortcutPlaceholder.length > 0
                                  ? self.shortcutPlaceholder
                                  : MASLocalizedString(@"Type Shortcut", @"Empty shortcut button in recording state")));
            [self drawInRect:shortcutRect withTitle:title alignment:NSCenterTextAlignment state:NSOnState];
        }
        else
        {
            [self drawInRect:self.bounds withTitle:MASLocalizedString(@"Record Shortcut", @"Empty shortcut button in normal state")
                   alignment:NSCenterTextAlignment state:NSOffState];
        }
    }
}


- (NSSize)intrinsicContentSize
{
    NSSize cellSize = _shortcutCell.cellSize;

    // Use a "fake" value for width.  Since determining the actual width requires information
    // that is not determined until drawRect: is called, it doesn't seem feasible to properly
    // calculate the intrinsic size without refactoring the code.  That would give better results,
    // however.

    // 120 is an arbitray number that seems to be wide enough for English localization.  This
    // may need to be adjusted for other locales/languages.

    // NOTE:  Simply returning cellSize results in a display that is sometimes correct
    // and sometimes not, and changes based on whether the mouse is hovering or not.
    return NSMakeSize(120, cellSize.height);
}


#pragma mark - Mouse handling

- (void)getShortcutRect:(CGRect *)shortcutRectRef hintRect:(CGRect *)hintRectRef
{
    CGRect shortcutRect, hintRect;
    CGFloat hintButtonWidth = MASHintButtonWidth;
    switch (self.style) {
        case MASShortcutViewStyleTexturedRect: hintButtonWidth += 2.0; break;
        case MASShortcutViewStyleRounded: hintButtonWidth += 3.0; break;
        case MASShortcutViewStyleFlat: hintButtonWidth -= 8.0 - (_shortcutCell.font.pointSize - MASButtonFontSize); break;
        default: break;
    }
    CGRectDivide(self.bounds, &hintRect, &shortcutRect, hintButtonWidth, CGRectMaxXEdge);
    if (shortcutRectRef)  *shortcutRectRef = shortcutRect;
    if (hintRectRef) *hintRectRef = hintRect;
}

- (BOOL)locationInShortcutRect:(CGPoint)location
{
    CGRect shortcutRect;
    [self getShortcutRect:&shortcutRect hintRect:NULL];
    return CGRectContainsPoint(shortcutRect, [self convertPoint:location fromView:nil]);
}

- (BOOL)locationInHintRect:(CGPoint)location
{
    CGRect hintRect;
    [self getShortcutRect:NULL hintRect:&hintRect];
    return CGRectContainsPoint(hintRect, [self convertPoint:location fromView:nil]);
}

- (void)mouseDown:(NSEvent *)event
{
    if (self.enabled) {
        if (self.shortcutValue) {
            if (self.recording) {
                if ([self locationInHintRect:event.locationInWindow]) {
                    self.recording = NO;
                }
            }
            else {
                if ([self locationInShortcutRect:event.locationInWindow]) {
                    self.recording = YES;
                }
                else {
                    self.shortcutValue = nil;
                }
            }
        }
        else {
            if (self.recording) {
                if ([self locationInHintRect:event.locationInWindow]) {
                    self.recording = NO;
                }
            }
            else {
                self.recording = YES;
            }
        }
    }
    else {
        [super mouseDown:event];
    }
}

#pragma mark - Handling mouse over

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    
    if (_hintArea) {
        [self removeTrackingArea:_hintArea];
        _hintArea = nil;
    }
    
    // Forbid hinting if view is disabled
    if (!self.enabled) return;
    
    CGRect hintRect;
    [self getShortcutRect:NULL hintRect:&hintRect];
    NSTrackingAreaOptions options = (NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingAssumeInside);
    _hintArea = [[NSTrackingArea alloc] initWithRect:hintRect options:options owner:self userInfo:nil];
    [self addTrackingArea:_hintArea];
}

- (void)setHinting:(BOOL)flag
{
    if (_hinting != flag) {
        _hinting = flag;
        [self invalidateIntrinsicContentSize];
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseEntered:(NSEvent *)event
{
    self.hinting = YES;
}

- (void)mouseExited:(NSEvent *)event
{
    self.hinting = NO;
}

void *kUserDataShortcut = &kUserDataShortcut;
void *kUserDataHint = &kUserDataHint;

- (void)resetToolTips
{
    if (_shortcutToolTipTag) {
        [self removeToolTip:_shortcutToolTipTag];
        _shortcutToolTipTag = 0;
    }
    if (_hintToolTipTag) {
        [self removeToolTip:_hintToolTipTag];
        _hintToolTipTag = 0;
    }
    
    if ((self.shortcutValue == nil) || self.recording || !self.enabled) return;

    CGRect shortcutRect, hintRect;
    [self getShortcutRect:&shortcutRect hintRect:&hintRect];
    _shortcutToolTipTag = [self addToolTipRect:shortcutRect owner:self userData:kUserDataShortcut];
    _hintToolTipTag = [self addToolTipRect:hintRect owner:self userData:kUserDataHint];
}

- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(CGPoint)point userData:(void *)data
{
    if (data == kUserDataShortcut) {
        return MASLocalizedString(@"Click to record new shortcut", @"Tooltip for non-empty shortcut button");
    }
    else if (data == kUserDataHint) {
        return MASLocalizedString(@"Delete shortcut", @"Tooltip for hint button near the non-empty shortcut");
    }
    return @"";
}

#pragma mark - Event monitoring

- (void)activateEventMonitoring:(BOOL)shouldActivate
{
    static BOOL isActive = NO;
    if (isActive == shouldActivate) return;
    isActive = shouldActivate;
    
    static id eventMonitor = nil;
    if (shouldActivate) {
        __unsafe_unretained MASShortcutView *weakSelf = self;
        NSEventMask eventMask = (NSKeyDownMask | NSFlagsChangedMask);
        eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:eventMask handler:^(NSEvent *event) {

            // Create a shortcut from the event
            MASShortcut *shortcut = [MASShortcut shortcutWithEvent:event];

            // Tab key must pass through.
            if (shortcut.keyCode == kVK_Tab){
                return event;
            }

            // If the shortcut is a plain Delete or Backspace, clear the current shortcut and cancel recording
            if (!shortcut.modifierFlags && ((shortcut.keyCode == kVK_Delete) || (shortcut.keyCode == kVK_ForwardDelete))) {
                weakSelf.shortcutValue = nil;
                weakSelf.recording = NO;
                event = nil;
            }

            // If the shortcut is a plain Esc, cancel recording
            else if (!shortcut.modifierFlags && shortcut.keyCode == kVK_Escape) {
                weakSelf.recording = NO;
                event = nil;
            }

            // If the shortcut is Cmd-W or Cmd-Q, cancel recording and pass the event through
            else if ((shortcut.modifierFlags == NSCommandKeyMask) && (shortcut.keyCode == kVK_ANSI_W || shortcut.keyCode == kVK_ANSI_Q)) {
                weakSelf.recording = NO;
            }

            else {
                // Verify possible shortcut
                if (shortcut.keyCodeString.length > 0) {
                    if (!weakSelf.shortcutValidator || [weakSelf.shortcutValidator isShortcutValid:shortcut]) {
                        // Verify that shortcut is not used
                        NSString *explanation = nil;
                        if ([weakSelf.shortcutValidator isShortcutAlreadyTakenBySystem:shortcut explanation:&explanation]) {
                            // Prevent cancel of recording when Alert window is key
                            [weakSelf activateResignObserver:NO];
                            [weakSelf activateEventMonitoring:NO];
                            NSString *format = MASLocalizedString(@"The key combination %@ cannot be used",
                                                                 @"Title for alert when shortcut is already used");
                            NSAlert* alert = [[NSAlert alloc]init];
                            alert.alertStyle = NSCriticalAlertStyle;
                            alert.informativeText = explanation;
                            alert.messageText = [NSString stringWithFormat:format, shortcut];
                            [alert addButtonWithTitle:MASLocalizedString(@"OK", @"Alert button when shortcut is already used")];

                            [alert runModal];
                            weakSelf.shortcutPlaceholder = nil;
                            [weakSelf activateResignObserver:YES];
                            [weakSelf activateEventMonitoring:YES];
                        }
                        else {
                            weakSelf.shortcutValue = shortcut;
                            weakSelf.recording = NO;
                        }
                    }
                    else {
                        // Key press with or without SHIFT is not valid input
                        NSBeep();
                    }
                }
                else {
                    // User is playing with modifier keys
                    weakSelf.shortcutPlaceholder = shortcut.modifierFlagsString;
                }
                event = nil;
            }
            return event;
        }];
    }
    else {
        [NSEvent removeMonitor:eventMonitor];
    }
}

- (void)activateResignObserver:(BOOL)shouldActivate
{
    static BOOL isActive = NO;
    if (isActive == shouldActivate) return;
    isActive = shouldActivate;
    
    static id observer = nil;
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    if (shouldActivate) {
        __unsafe_unretained MASShortcutView *weakSelf = self;
        observer = [notificationCenter addObserverForName:NSWindowDidResignKeyNotification object:self.window
                                                queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
                                                    weakSelf.recording = NO;
                                                }];
    }
    else {
        [notificationCenter removeObserver:observer];
    }
}

#pragma mark Bindings

// http://tomdalling.com/blog/cocoa/implementing-your-own-cocoa-bindings/
-(void) propagateValue:(id)value forBinding:(NSString*)binding
{
    NSParameterAssert(binding != nil);

    //WARNING: bindingInfo contains NSNull, so it must be accounted for
    NSDictionary* bindingInfo = [self infoForBinding:binding];
    if(!bindingInfo)
        return; //there is no binding

    //apply the value transformer, if one has been set
    NSDictionary* bindingOptions = [bindingInfo objectForKey:NSOptionsKey];
    if(bindingOptions){
        NSValueTransformer* transformer = [bindingOptions valueForKey:NSValueTransformerBindingOption];
        if(!transformer || (id)transformer == [NSNull null]){
            NSString* transformerName = [bindingOptions valueForKey:NSValueTransformerNameBindingOption];
            if(transformerName && (id)transformerName != [NSNull null]){
                transformer = [NSValueTransformer valueTransformerForName:transformerName];
            }
        }

        if(transformer && (id)transformer != [NSNull null]){
            if([[transformer class] allowsReverseTransformation]){
                value = [transformer reverseTransformedValue:value];
            } else {
                NSLog(@"WARNING: binding \"%@\" has value transformer, but it doesn't allow reverse transformations in %s", binding, __PRETTY_FUNCTION__);
            }
        }
    }

    id boundObject = [bindingInfo objectForKey:NSObservedObjectKey];
    if(!boundObject || boundObject == [NSNull null]){
        NSLog(@"ERROR: NSObservedObjectKey was nil for binding \"%@\" in %s", binding, __PRETTY_FUNCTION__);
        return;
    }

    NSString* boundKeyPath = [bindingInfo objectForKey:NSObservedKeyPathKey];
    if(!boundKeyPath || (id)boundKeyPath == [NSNull null]){
        NSLog(@"ERROR: NSObservedKeyPathKey was nil for binding \"%@\" in %s", binding, __PRETTY_FUNCTION__);
        return;
    }

    [boundObject setValue:value forKeyPath:boundKeyPath];
}

#pragma mark - Accessibility

- (NSString *)accessibilityHelp
{
    return MASLocalizedString(@"To record a new shortcut, click this button, and then type the"
                             @" new shortcut, or press delete to clear an existing shortcut.",
                             @"VoiceOver shortcut help");
}

- (NSString *)accessibilityLabel
{
    NSString* title = _shortcutValue.description ?: @"Empty";
    title = [title stringByAppendingFormat:@" %@", MASLocalizedString(@"keyboard shortcut", @"VoiceOver title")];
    return title;
}

- (BOOL)accessibilityPerformPress
{
    if (self.isRecording == NO) {
        self.recording = YES;
        return YES;
    }
    else {
        return NO;
    }
}

- (NSString *)accessibilityRole
{
    return NSAccessibilityButtonRole;
}

- (BOOL)acceptsFirstResponder
{
    return _acceptsFirstResponder;
}

- (void)setAcceptsFirstResponder:(BOOL)value
{
    _acceptsFirstResponder = value;
}

- (BOOL)becomeFirstResponder
{
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay:YES];
    return [super becomeFirstResponder];
}

- (BOOL)resignFirstResponder
{
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay:YES];
    return [super resignFirstResponder];
}

- (void)drawFocusRingMask
{
    [_shortcutCell drawFocusRingMaskWithFrame:[self bounds] inView:self];
}

- (NSRect)focusRingMaskBounds
{
    return [self bounds];
}

@end
