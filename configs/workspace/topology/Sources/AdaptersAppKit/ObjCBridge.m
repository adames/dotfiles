#import "AdaptersAppKitObjC.h"

@implementation WSObjCWindowDelegate

- (void)windowDidChangeScreen:(NSNotification *)notification {
    NSWindow *window = notification.object;
    if (self.onScreenChange) { self.onScreenChange(window); }
    [self restoreFocusForWindow:window];
}

- (void)windowDidChangeBackingProperties:(NSNotification *)notification {
    NSWindow *window = notification.object;
    if (self.onBackingChange) { self.onBackingChange(window); }
}

- (void)restoreFocusForWindow:(NSWindow *)window {
    // When a window crosses displays, the system may drop first-responder.
    // Best-effort restore to the content view; consumers can override via the
    // Swift WorkspaceWindowDelegate for finer-grained behavior.
    if (window.firstResponder == nil) {
        [window makeFirstResponder:window.contentView];
    }
}

@end
