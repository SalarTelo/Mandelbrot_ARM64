#import <Cocoa/Cocoa.h>
#import <mach/mach_time.h>
#import <QuartzCore/QuartzCore.h>

#import "objc_window.h"

// Forward declarations for ObjC types
@interface WindowDelegate : NSObject <NSWindowDelegate>
- (BOOL)windowShouldClose:(NSWindow *)sender;
- (void)windowWillClose:(NSNotification *)notification;
- (void)windowDidResize:(NSNotification *)notification;
@end

@interface WindowView : NSView
- (void)drawRect:(NSRect)dirtyRect;
- (void)updateLayer;
+ (BOOL)wantsUpdateLayer;

@property(nonatomic) const void *pixelData;
@property(nonatomic) int stride;
@property(nonatomic) int width;
@property(nonatomic) int height;
@end

enum {
    kMouseButtonCount = 3
};

// Global window state - kept minimal.
static struct {
    NSWindow *window;
    WindowView *view;
    WindowDelegate *delegate;
    BOOL should_close;
    // Time tracking
    mach_timebase_info_data_t timebase;
    uint64_t start_ticks;
    uint64_t last_ns;
    uint64_t delta_ns;
    // Mouse state
    int mouse_buttons[kMouseButtonCount];   // 0:left,1:right,2:middle (1=down,0=up)
    double mouse_x;
    double mouse_y;
} g_window_state = {
    NULL, NULL, NULL, NO, {0, 0}, 0, 0, 0, {0, 0, 0}, 0.0, 0.0
};

static void reset_window_state(void) {
    g_window_state.window = NULL;
    g_window_state.view = NULL;
    g_window_state.delegate = NULL;
    g_window_state.should_close = NO;
    g_window_state.timebase.numer = 0;
    g_window_state.timebase.denom = 0;
    g_window_state.start_ticks = 0;
    g_window_state.last_ns = 0;
    g_window_state.delta_ns = 0;
    for (int i = 0; i < kMouseButtonCount; i++) {
        g_window_state.mouse_buttons[i] = 0;
    }
    g_window_state.mouse_x = 0.0;
    g_window_state.mouse_y = 0.0;
}

static void init_timebase_if_needed(void) {
    if (g_window_state.timebase.denom != 0) {
        return;
    }
    mach_timebase_info(&g_window_state.timebase);
    g_window_state.start_ticks = mach_absolute_time();
    g_window_state.last_ns = 0;
    g_window_state.delta_ns = 0;
}

static void update_time(void) {
    if (g_window_state.timebase.denom == 0) {
        init_timebase_if_needed();
    }

    uint64_t now = mach_absolute_time();
    uint64_t elapsed_ticks = now - g_window_state.start_ticks;
    uint64_t elapsed_ns = (uint64_t)((elapsed_ticks * (double)g_window_state.timebase.numer) /
        (double)g_window_state.timebase.denom);

    if (g_window_state.last_ns == 0) {
        g_window_state.delta_ns = 0;
    } else if (elapsed_ns >= g_window_state.last_ns) {
        g_window_state.delta_ns = elapsed_ns - g_window_state.last_ns;
    } else {
        g_window_state.delta_ns = 0;
    }

    g_window_state.last_ns = elapsed_ns;
}

// WindowDelegate implementation
@implementation WindowDelegate

- (BOOL)windowShouldClose:(NSWindow *)sender {
    g_window_state.should_close = YES;
    return NO;  // We handle closing manually.
}

- (void)windowWillClose:(NSNotification *)notification {
    g_window_state.window = NULL;
    g_window_state.should_close = YES;
}

- (void)windowDidResize:(NSNotification *)notification {
    if (g_window_state.view == NULL) {
        return;
    }
    // Keep the backing buffer size fixed; the view scales it in drawRect.
    [g_window_state.view setNeedsDisplay:YES];
}

@end

// WindowView implementation - renders the framebuffer
@implementation WindowView
{
    const void *_lastPixelData;
    int _lastStride;
    int _lastWidth;
    int _lastHeight;
    CGColorSpaceRef _colorSpace;
    CGDataProviderRef _provider;
    CGImageRef _image;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        _colorSpace = CGColorSpaceCreateDeviceRGB();
        // Make scaling nearest-neighbor for crisp pixels
        self.layer.contentsGravity = kCAGravityResize;
        self.layer.magnificationFilter = kCAFilterNearest;
        self.layer.minificationFilter = kCAFilterNearest;
    }
    return self;
}

- (void)dealloc {
    if (_image != NULL) {
        CGImageRelease(_image);
    }
    if (_provider != NULL) {
        CGDataProviderRelease(_provider);
    }
    if (_colorSpace != NULL) {
        CGColorSpaceRelease(_colorSpace);
    }
    [super dealloc];
}

- (void)updateImageIfNeeded {
    if (self.pixelData == NULL) {
        return;
    }

    if (self.stride <= 0 || self.width <= 0 || self.height <= 0) {
        return;
    }

    if (_image != NULL &&
        _lastPixelData == self.pixelData &&
        _lastStride == self.stride &&
        _lastWidth == self.width &&
        _lastHeight == self.height) {
        return;
    }

    if (_image != NULL) {
        CGImageRelease(_image);
        _image = NULL;
    }
    if (_provider != NULL) {
        CGDataProviderRelease(_provider);
        _provider = NULL;
    }

    size_t bytes = (size_t)self.stride * (size_t)self.height;
    _provider = CGDataProviderCreateWithData(NULL, self.pixelData, bytes, NULL);
    if (_provider != NULL) {
        _image = CGImageCreate(
            self.width,
            self.height,
            8,
            32,
            self.stride,
            _colorSpace,
            kCGImageAlphaLast | kCGBitmapByteOrder32Big,
            _provider,
            NULL,
            false,
            kCGRenderingIntentDefault
        );
    }

    _lastPixelData = self.pixelData;
    _lastStride = self.stride;
    _lastWidth = self.width;
    _lastHeight = self.height;
}

- (void)updateLayer {
    [self updateImageIfNeeded];
    if (_image != NULL) {
        self.layer.contents = (__bridge id)_image;
    } else {
        self.layer.contents = nil;
    }
}

+ (BOOL)wantsUpdateLayer {
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    if (self.pixelData == NULL) {
        [[NSColor blackColor] setFill];
        NSRectFill(dirtyRect);
        return;
    }

    [self updateImageIfNeeded];
    if (_image != NULL) {
        CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
        CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
        CGContextDrawImage(ctx, self.bounds, _image);
    }
}

@end

// C API Implementation

int window_create(int width, int height) {
    // Return early if window already exists.
    if (g_window_state.window != NULL) {
        return -1;
    }
    reset_window_state();

    // Ensure NSApplication is initialized (safe to call multiple times).
    NSApplication *app = [NSApplication sharedApplication];
    // Make app regular (shows Dock icon and can have windows).
    [app setActivationPolicy:NSApplicationActivationPolicyRegular];
    // Finish launching to set up event system.
    [app finishLaunching];

    g_window_state.should_close = NO;

    // Create the window.
    NSRect frame = NSMakeRect(1000, 200, width, height);
    g_window_state.window = [[NSWindow alloc]
        initWithContentRect:frame
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable)
        backing:NSBackingStoreBuffered
        defer:NO];

    if (g_window_state.window == NULL) {
        return -1;
    }

    // Create delegate.
    g_window_state.delegate = [[WindowDelegate alloc] init];
    if (g_window_state.delegate == NULL) {
        [g_window_state.window release];
        g_window_state.window = NULL;
        return -1;
    }
    [g_window_state.window setDelegate:g_window_state.delegate];

    // Create view.
    g_window_state.view = [[WindowView alloc] initWithFrame:frame];
    if (g_window_state.view == NULL) {
        [g_window_state.delegate release];
        [g_window_state.window release];
        g_window_state.window = NULL;
        g_window_state.delegate = NULL;
        return -1;
    }
    g_window_state.view.width = width;
    g_window_state.view.height = height;
    g_window_state.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // Set the view as content.
    [g_window_state.window setContentView:g_window_state.view];

    // Set window title.
    NSString *windowTitle = @"My wacky little program";
    [g_window_state.window setTitle:windowTitle];

    // Make window visible and bring to front.
    [g_window_state.window makeKeyAndOrderFront:nil];
    [app activateIgnoringOtherApps:YES];

    return 0;  // Success.
}

void window_poll_events(void) {
    if (g_window_state.window == NULL) {
        return;
    }

    update_time();

    NSEvent *event = nil;
    NSEventMask mask = NSEventMaskAny;
    do {
        @autoreleasepool {
            event = [[NSApplication sharedApplication]
                nextEventMatchingMask:mask
                untilDate:[NSDate distantPast]
                inMode:NSDefaultRunLoopMode
                dequeue:YES];
        }

        if (event == nil) {
            break;
        }

        switch ([event type]) {
            case NSEventTypeLeftMouseDown:   g_window_state.mouse_buttons[0] = 1; break;
            case NSEventTypeLeftMouseUp:     g_window_state.mouse_buttons[0] = 0; break;
            case NSEventTypeRightMouseDown:  g_window_state.mouse_buttons[1] = 1; break;
            case NSEventTypeRightMouseUp:    g_window_state.mouse_buttons[1] = 0; break;
            case NSEventTypeOtherMouseDown:  g_window_state.mouse_buttons[2] = 1; break;
            case NSEventTypeOtherMouseUp:    g_window_state.mouse_buttons[2] = 0; break;
            case NSEventTypeMouseMoved:
            case NSEventTypeLeftMouseDragged:
            case NSEventTypeRightMouseDragged:
            case NSEventTypeOtherMouseDragged:
            {
                NSPoint p = [event locationInWindow];
                g_window_state.mouse_x = p.x;
                g_window_state.mouse_y = p.y;
                break;
            }
            default:
                break;
        }

        [[NSApplication sharedApplication] sendEvent:event];
    } while (event != nil);

    // Update mouse position even when there are no motion events.
    if (g_window_state.window != NULL) {
        NSPoint p = [g_window_state.window mouseLocationOutsideOfEventStream];
        g_window_state.mouse_x = p.x;
        g_window_state.mouse_y = p.y;
    }
}

int window_should_close(void) {
    return (int)g_window_state.should_close || g_window_state.window == NULL;
}

void window_present(const void *pixel_data, int stride) {
    if (g_window_state.view == NULL) {
        return;
    }

    g_window_state.view.pixelData = pixel_data;
    g_window_state.view.stride = stride;

    // Trigger redraw; layer-backed so updateLayer will set contents atomically.
    [g_window_state.view setNeedsDisplay:YES];
    [g_window_state.view displayIfNeeded];
}

void window_destroy(void) {
    if (g_window_state.window != NULL) {
        [g_window_state.window setDelegate:nil];
        [g_window_state.window close];
    }

    if (g_window_state.view != NULL) {
        [g_window_state.view release];
        g_window_state.view = NULL;
    }

    if (g_window_state.delegate != NULL) {
        [g_window_state.delegate release];
        g_window_state.delegate = NULL;
    }

    if (g_window_state.window != NULL) {
        [g_window_state.window release];
        g_window_state.window = NULL;
    }

    g_window_state.should_close = YES;
}

uint64_t window_get_time_ns(void) {
    return g_window_state.last_ns;
}

uint64_t window_get_delta_ns(void) {
    return g_window_state.delta_ns;
}

double window_get_time_seconds(void) {
    return (double)g_window_state.last_ns / 1e9;
}

float window_get_time_seconds_f32(void) {
    return (float)g_window_state.last_ns / 1e9f;
}

float window_get_delta_seconds_f32(void) {
    return (float)g_window_state.delta_ns / 1e9f;
}

void window_get_mouse_uv_f32(float *out_u, float *out_v) {
    float u = 0.0f;
    float v = 0.0f;

    if (g_window_state.view != NULL) {
        NSPoint point = NSMakePoint(g_window_state.mouse_x, g_window_state.mouse_y);
        NSPoint backing = [g_window_state.view convertPointToBacking:point];
        NSRect bounds = [g_window_state.view bounds];
        NSRect backing_bounds = [g_window_state.view convertRectToBacking:bounds];

        double width = backing_bounds.size.width;
        double height = backing_bounds.size.height;

        if (width > 0.0 && height > 0.0) {
            double bx = backing.x;
            double by = backing.y;

            if (bx < 0.0) bx = 0.0;
            if (by < 0.0) by = 0.0;
            if (bx > width) bx = width;
            if (by > height) by = height;

            u = (float)(bx / width);
            v = (float)(by / height);
        }
    }

    if (out_u != NULL) {
        *out_u = u;
    }
    if (out_v != NULL) {
        *out_v = v;
    }
}

int window_get_mouse_button(int button) {
    if (button < 0 || button >= kMouseButtonCount) {
        return 0;
    }
    return g_window_state.mouse_buttons[button];
}

void window_get_mouse_position(double *out_x, double *out_y) {
    if (out_x != NULL) {
        *out_x = g_window_state.mouse_x;
    }
    if (out_y != NULL) {
        *out_y = g_window_state.mouse_y;
    }
}
