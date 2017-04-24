[![Build Status](https://travis-ci.org/shpakovski/MASShortcut.svg?branch=master)](https://travis-ci.org/shpakovski/MASShortcut)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)

# Intro

Some time ago Cocoa developers used a brilliant framework [ShortcutRecorder](http://wafflesoftware.net/shortcut/) for managing keyboard shortcuts in application preferences. However, it became incompatible with the new plugin architecture of Xcode 4.

The MASShortcut project introduces a modern API and user interface for recording, storing and using system-wide keyboard shortcuts.

![Screenshot of the demo project](https://raw.githubusercontent.com/shpakovski/MASShortcut/master/Demo/screenshot.png "This is how the demo looks like")

Features:

* Record and display keyboard shortcuts
* Watch for shortcuts and execute actions, system-wide
* A nice, [documented API](http://cocoadocs.org/docsets/MASShortcut/)
* Can be configured to be compatible with Shortcut Recorder
* Can be installed both through CocoaPods and as a Git submodule
* Mac App Store friendly
* Works on OS X 10.6 and up
* Hacking-friendly codebase covered with tests

Partially done:

* Accessibility support. There’s some basic accessibility code, testers and feedback welcome.
* Localisation. The English and Czech localization should be complete, there’s basic support for German, French, Spanish, Italian, and Japanese. If you’re a native speaker in one of the mentioned languages, please test the localization and report issues or add missing strings.

Pull requests welcome :)

# Installation

You can use [CocoaPods](http://cocoapods.org/), adding the following line to your Podfile:

    pod 'MASShortcut'

If you want to stick to the 1.x branch, you can use the version smart match operator:

    pod 'MASShortcut', '~> 1'

You can also install via [Carthage](https://github.com/Carthage/Carthage), or you can use Git submodules and link against the MASShortcut framework manually.

To build from the command line, type 'make release'. The framework will be created in a temporary directory and revealed in Finder when the build is complete.

# Usage

I hope, it is really easy:

```objective-c
#import <MASShortcut/Shortcut.h>

// Drop a custom view into XIB, set its class to MASShortcutView
// and its height to 19. If you select another appearance style,
// look up the correct height values in MASShortcutView.h.
@property (nonatomic, weak) IBOutlet MASShortcutView *shortcutView;

// Pick a preference key to store the shortcut between launches
static NSString *const kPreferenceGlobalShortcut = @"GlobalShortcut";

// Associate the shortcut view with user defaults
self.shortcutView.associatedUserDefaultsKey = kPreferenceGlobalShortcut;

// Associate the preference key with an action
[[MASShortcutBinder sharedBinder]
    bindShortcutWithDefaultsKey:kPreferenceGlobalShortcut
    toAction:^{
    // Let me know if you find a better or a more convenient API.
}];
```

You can see a real usage example in the Demo target. Enjoy!

# Shortcut Recorder Compatibility

By default, MASShortcut uses a different User Defaults storage format incompatible with Shortcut Recorder. But it’s easily possible to change that, so that you can replace Shortcut Recorder with MASShortcut without having to migrate the shortcuts previously stored by your apps. There are two parts of the story:

If you bind the recorder control (`MASShortcutView`) to User defaults, set the Value Transformer field in the Interface Builder to `MASDictionaryTransformer`. This makes sure the shortcuts are written in the Shortcut Recorder format.

If you use `MASShortcutBinder` to automatically load shortcuts from User Defaults, set the `bindingOptions` accordingly:

```objective-c
[[MASShortcutBinder sharedBinder] setBindingOptions:@{NSValueTransformerNameBindingOption:MASDictionaryTransformerName}];
```

This makes sure that the shortcuts in the Shortcut Recorder format are loaded correctly.

# Notifications

By registering for KVO notifications from `NSUserDefaultsController`, you can get a callback whenever a user changes the shortcut, allowing you to perform any UI updates, or other code handling tasks.

This is just as easy to implement:
    
```objective-c
// Declare an ivar for key path in the user defaults controller
NSString *_observableKeyPath;
    
// Make a global context reference
void *kGlobalShortcutContext = &kGlobalShortcutContext;
    
// Implement when loading view
_observableKeyPath = [@"values." stringByAppendingString:kPreferenceGlobalShortcut];
[[NSUserDefaultsController sharedUserDefaultsController] addObserver:self forKeyPath:_observableKeyPath
                                                             options:NSKeyValueObservingOptionInitial
                                                             context:kGlobalShortcutContext];

// Capture the KVO change and do something
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)obj
                        change:(NSDictionary *)change context:(void *)ctx
{
    if (ctx == kGlobalShortcutContext) {
        NSLog(@"Shortcut has changed");
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:obj change:change context:ctx];
    }
}

// Do not forget to remove the observer
[[NSUserDefaultsController sharedUserDefaultsController] removeObserver:self
                                                             forKeyPath:_observableKeyPath
                                                                context:kGlobalShortcutContext];
```

# Using in Swift projects

  1. Install as a Pod using the latest CocoaPods with Swift support.
  2. Create a bridging header file [using the instructions here](http://swiftalicio.us/2014/11/using-cocoapods-from-swift/)
  3. Your bridging header file should contain the following [two](https://github.com/shpakovski/MASShortcut/issues/36) imports:

```objective-c
#import <Cocoa/Cocoa.h>
#import <MASShortcut/Shortcut.h>
```

# Copyright

MASShortcut is licensed under the 2-clause BSD license.
