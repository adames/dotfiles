// Public header for the Objective-C compatibility shim.
//
// Provides a sample `NSWindowDelegate` subclass that adopts the per-window
// screen-change + backing-properties contract described in the README.
// Swift code generally uses `WorkspaceWindowDelegate` (Swift) directly, but
// the ObjC class is exported for AppKit codebases that prefer ObjC delegates.

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WSObjCWindowDelegate : NSObject <NSWindowDelegate>

/// Called when the window's screen changes. Override or set a block in Swift.
@property (nonatomic, copy, nullable) void (^onScreenChange)(NSWindow *window);

/// Called when the window's backing scale factor or color space changes.
@property (nonatomic, copy, nullable) void (^onBackingChange)(NSWindow *window);

@end

NS_ASSUME_NONNULL_END
