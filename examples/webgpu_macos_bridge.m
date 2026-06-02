#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

void *webgpu_macos_main_window_metal_layer(void) {
	NSWindow *window = [NSApp mainWindow];
	if (window == nil) {
		window = [NSApp keyWindow];
	}
	if (window == nil) {
		return nil;
	}

	NSView *contentView = [window contentView];
	if (contentView == nil) {
		return nil;
	}

	return (__bridge void *)[contentView layer];
}