#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>

// External ARM64 assembly functions
extern int mandelbrot_point(double x, double y, int max_iter);
extern void mandelbrot_compute(unsigned char* buffer, int width, int height,
                               double x_min, double x_max,
                               double y_min, double y_max,
                               int max_iterations);

// Window dimensions
#define WINDOW_WIDTH 800
#define WINDOW_HEIGHT 600
#define MAX_ITERATIONS 256

// Mandelbrot set coordinate range
#define X_MIN -2.5
#define X_MAX 1.0
#define Y_MIN -1.0
#define Y_MAX 1.0

@interface MandelbrotView : NSView {
    unsigned char* imageBuffer;
    NSBitmapImageRep* bitmap;
}
@end

@implementation MandelbrotView

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Allocate buffer for RGBA pixels
        int width = (int)frame.size.width;
        int height = (int)frame.size.height;
        imageBuffer = (unsigned char*)malloc(width * height * 4);
        
        if (imageBuffer) {
            // Compute Mandelbrot set using ARM64 assembly
            NSLog(@"Computing Mandelbrot set (%dx%d)...", width, height);
            mandelbrot_compute(imageBuffer, width, height,
                             X_MIN, X_MAX, Y_MIN, Y_MAX,
                             MAX_ITERATIONS);
            NSLog(@"Computation complete!");
            
            // Create bitmap from buffer
            bitmap = [[NSBitmapImageRep alloc]
                     initWithBitmapDataPlanes:&imageBuffer
                     pixelsWide:width
                     pixelsHigh:height
                     bitsPerSample:8
                     samplesPerPixel:4
                     hasAlpha:YES
                     isPlanar:NO
                     colorSpaceName:NSDeviceRGBColorSpace
                     bytesPerRow:width * 4
                     bitsPerPixel:32];
        }
    }
    return self;
}

- (void)dealloc {
    if (imageBuffer) {
        free(imageBuffer);
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    if (bitmap) {
        [bitmap drawInRect:self.bounds];
    }
}

- (BOOL)isOpaque {
    return YES;
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate> {
    NSWindow* window;
}
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    // Create window
    NSRect frame = NSMakeRect(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT);
    NSUInteger styleMask = NSWindowStyleMaskTitled | 
                          NSWindowStyleMaskClosable | 
                          NSWindowStyleMaskMiniaturizable;
    
    window = [[NSWindow alloc] initWithContentRect:frame
                                         styleMask:styleMask
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    
    [window setTitle:@"Mandelbrot Set - ARM64"];
    [window center];
    
    // Create and set content view
    MandelbrotView* view = [[MandelbrotView alloc] initWithFrame:frame];
    [window setContentView:view];
    
    // Show window
    [window makeKeyAndOrderFront:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
    return YES;
}

@end

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        NSApplication* app = [NSApplication sharedApplication];
        AppDelegate* delegate = [[AppDelegate alloc] init];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
