#import "launcher_ffi.h"
#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>

// Forward declarations
@class LauncherWindow;
@class LauncherTextField;

#pragma mark - Launcher Window

@interface LauncherWindow : NSWindow
@end

@implementation LauncherWindow
- (BOOL)canBecomeKey { return YES; }
- (BOOL)canBecomeMain { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
@end

#pragma mark - Launcher TextField

@interface LauncherTextField : NSTextField
@property (nonatomic, copy) void (^onSubmit)(void);
@property (nonatomic, copy) void (^onCommandReturn)(void);
@property (nonatomic, copy) void (^onOptionReturn)(void);
@property (nonatomic, copy) void (^onEscape)(void);
@end

@implementation LauncherTextField

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (event.type != NSEventTypeKeyDown) {
        return [super performKeyEquivalent:event];
    }

    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    BOOL isReturn = event.keyCode == 36 || event.keyCode == 76;

    if (isReturn) {
        if ((flags & NSEventModifierFlagCommand) && !(flags & NSEventModifierFlagOption)) {
            if (self.onCommandReturn) self.onCommandReturn();
            return YES;
        }
        if ((flags & NSEventModifierFlagOption) && !(flags & NSEventModifierFlagCommand)) {
            if (self.onOptionReturn) self.onOptionReturn();
            return YES;
        }
    }

    // Standard shortcuts
    if (flags & NSEventModifierFlagCommand) {
        NSString *key = event.charactersIgnoringModifiers.lowercaseString;
        if ([key isEqualToString:@"a"]) {
            [NSApp sendAction:@selector(selectAll:) to:nil from:self];
            return YES;
        }
        if ([key isEqualToString:@"c"]) {
            [NSApp sendAction:@selector(copy:) to:nil from:self];
            return YES;
        }
        if ([key isEqualToString:@"x"]) {
            [NSApp sendAction:@selector(cut:) to:nil from:self];
            return YES;
        }
        if ([key isEqualToString:@"v"]) {
            [NSApp sendAction:@selector(paste:) to:nil from:self];
            return YES;
        }
    }

    return [super performKeyEquivalent:event];
}

- (void)keyDown:(NSEvent *)event {
    switch (event.keyCode) {
        case 53: // Escape
            if (self.onEscape) self.onEscape();
            break;
        case 36: // Return
        case 76: // Keypad Enter
            if (event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagOption)) {
                return; // Handled by performKeyEquivalent
            }
            if (self.onSubmit) self.onSubmit();
            break;
        default:
            [super keyDown:event];
    }
}

@end

#pragma mark - Launcher Controller

@interface LauncherController : NSObject <NSWindowDelegate>
@property (nonatomic, strong) LauncherWindow *window;
@property (nonatomic, strong) LauncherTextField *textField;
@property (nonatomic, strong) NSRunningApplication *previousApp;
@property (nonatomic, strong) id escapeMonitor;
@property (nonatomic, strong) id escapeMonitorLocal;
@property (nonatomic, copy) void (^completion)(LauncherResultCode, NSString *);
+ (instancetype)shared;
- (void)showWithPlaceholder:(NSString *)placeholder completion:(void (^)(LauncherResultCode, NSString *))completion;
- (void)hide;
- (BOOL)isVisible;
@end

@implementation LauncherController

+ (instancetype)shared {
    static LauncherController *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[LauncherController alloc] init];
    });
    return instance;
}

- (void)showWithPlaceholder:(NSString *)placeholder completion:(void (^)(LauncherResultCode, NSString *))completion {
    self.previousApp = NSWorkspace.sharedWorkspace.frontmostApplication;
    self.completion = completion;

    if (!self.window) {
        [self createWindow];
    }

    self.textField.placeholderString = placeholder.length > 0 ? placeholder : @"Search...";
    self.textField.stringValue = @"";

    // Activate app
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    if (@available(macOS 14, *)) {
        [NSApp activate];
    } else {
        [NSApp activateIgnoringOtherApps:YES];
    }

    // Position window
    NSScreen *screen = NSScreen.mainScreen;
    if (!screen) return;

    CGFloat width = 640;
    CGFloat height = 56;
    CGFloat x = (screen.frame.size.width - width) / 2;
    CGFloat y = (screen.frame.size.height - height) / 2 + 140;

    [self.window setFrame:NSMakeRect(x, y, width, height) display:YES];
    [self.window makeKeyAndOrderFront:nil];

    // Multiple focus attempts
    for (int i = 0; i < 3; i++) {
        double delay = (i == 0) ? 0.05 : (i == 1) ? 0.15 : 0.3;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (@available(macOS 14, *)) {
                [NSApp activate];
            } else {
                [NSApp activateIgnoringOtherApps:YES];
            }
            [self.window makeKeyWindow];
            [self.window makeFirstResponder:self.textField];
        });
    }

    [self registerEscapeMonitor];
}

- (void)hide {
    [self hideWithResult:LAUNCHER_DISMISSED query:nil];
}

- (void)hideWithResult:(LauncherResultCode)result query:(NSString *)query {
    if (!self.window.isVisible) return;

    [self.window orderOut:nil];
    [self unregisterEscapeMonitor];

    // Restore previous app
    if (self.previousApp && self.previousApp.processIdentifier != NSRunningApplication.currentApplication.processIdentifier) {
        if (@available(macOS 14, *)) {
            [self.previousApp activateWithOptions:0];
        } else {
            [self.previousApp activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        }
    }
    self.previousApp = nil;

    if (self.completion) {
        void (^cb)(LauncherResultCode, NSString *) = self.completion;
        self.completion = nil;
        cb(result, query);
    }
}

- (BOOL)isVisible {
    return self.window.isVisible;
}

- (void)createWindow {
    LauncherWindow *window = [[LauncherWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 640, 56)
        styleMask:NSWindowStyleMaskBorderless
        backing:NSBackingStoreBuffered
        defer:NO];

    window.titleVisibility = NSWindowTitleHidden;
    window.titlebarAppearsTransparent = YES;
    window.opaque = NO;
    window.backgroundColor = NSColor.clearColor;
    window.releasedWhenClosed = NO;
    window.level = NSFloatingWindowLevel;
    window.hasShadow = YES;
    window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;

    // Visual effect background
    NSVisualEffectView *visualEffect = [[NSVisualEffectView alloc] initWithFrame:window.contentView.bounds];
    visualEffect.material = NSVisualEffectMaterialHUDWindow;
    visualEffect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    visualEffect.state = NSVisualEffectStateActive;
    visualEffect.wantsLayer = YES;
    visualEffect.layer.cornerRadius = 12;
    visualEffect.layer.masksToBounds = YES;
    visualEffect.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // Text field
    LauncherTextField *field = [[LauncherTextField alloc] initWithFrame:NSZeroRect];
    field.bordered = NO;
    field.bezeled = NO;
    field.focusRingType = NSFocusRingTypeNone;
    field.font = [NSFont systemFontOfSize:18 weight:NSFontWeightRegular];
    field.backgroundColor = NSColor.clearColor;
    field.textColor = NSColor.labelColor;
    field.translatesAutoresizingMaskIntoConstraints = NO;

    __weak typeof(self) weakSelf = self;
    field.onSubmit = ^{
        [weakSelf submitWithResult:LAUNCHER_SUBMITTED];
    };
    field.onCommandReturn = ^{
        [weakSelf submitWithResult:LAUNCHER_COMMAND];
    };
    field.onOptionReturn = ^{
        [weakSelf submitWithResult:LAUNCHER_OPTION];
    };
    field.onEscape = ^{
        [weakSelf hideWithResult:LAUNCHER_DISMISSED query:nil];
    };

    [visualEffect addSubview:field];
    [NSLayoutConstraint activateConstraints:@[
        [field.leadingAnchor constraintEqualToAnchor:visualEffect.leadingAnchor constant:20],
        [field.trailingAnchor constraintEqualToAnchor:visualEffect.trailingAnchor constant:-20],
        [field.centerYAnchor constraintEqualToAnchor:visualEffect.centerYAnchor]
    ]];

    window.contentView = visualEffect;
    self.window = window;
    self.textField = field;
}

- (void)submitWithResult:(LauncherResultCode)result {
    NSString *query = [self.textField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (query.length == 0) {
        [self hideWithResult:LAUNCHER_DISMISSED query:nil];
        return;
    }
    [self hideWithResult:result query:query];
}

- (void)registerEscapeMonitor {
    if (!self.escapeMonitor) {
        __weak typeof(self) weakSelf = self;
        self.escapeMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^(NSEvent *event) {
            if (event.keyCode == 53) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf hideWithResult:LAUNCHER_DISMISSED query:nil];
                });
            }
        }];
    }

    if (!self.escapeMonitorLocal) {
        __weak typeof(self) weakSelf = self;
        self.escapeMonitorLocal = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
            if (event.keyCode == 53) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf hideWithResult:LAUNCHER_DISMISSED query:nil];
                });
                return nil;
            }
            return event;
        }];
    }
}

- (void)unregisterEscapeMonitor {
    if (self.escapeMonitor) {
        [NSEvent removeMonitor:self.escapeMonitor];
        self.escapeMonitor = nil;
    }
    if (self.escapeMonitorLocal) {
        [NSEvent removeMonitor:self.escapeMonitorLocal];
        self.escapeMonitorLocal = nil;
    }
}

@end

#pragma mark - C Interface

void launcher_show(const char* placeholder, launcher_callback_t callback, void* context) {
    NSString *placeholderStr = placeholder ? [NSString stringWithUTF8String:placeholder] : @"";

    dispatch_async(dispatch_get_main_queue(), ^{
        [[LauncherController shared] showWithPlaceholder:placeholderStr completion:^(LauncherResultCode result, NSString *query) {
            if (callback) {
                callback(result, query ? query.UTF8String : NULL, context);
            }
        }];
    });
}

void launcher_hide(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[LauncherController shared] hide];
    });
}

int32_t launcher_is_visible(void) {
    __block BOOL visible = NO;
    if ([NSThread isMainThread]) {
        visible = [[LauncherController shared] isVisible];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            visible = [[LauncherController shared] isVisible];
        });
    }
    return visible ? 1 : 0;
}

int32_t launcher_show_sync(const char* placeholder, char* query_buffer, int32_t buffer_size) {
    __block LauncherResultCode result = LAUNCHER_DISMISSED;
    __block NSString *queryStr = nil;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *placeholderStr = placeholder ? [NSString stringWithUTF8String:placeholder] : @"";
        [[LauncherController shared] showWithPlaceholder:placeholderStr completion:^(LauncherResultCode r, NSString *q) {
            result = r;
            queryStr = q;
            dispatch_semaphore_signal(semaphore);
        }];
    });

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    if (query_buffer && buffer_size > 0) {
        if (queryStr) {
            strncpy(query_buffer, queryStr.UTF8String, buffer_size - 1);
            query_buffer[buffer_size - 1] = '\0';
        } else {
            query_buffer[0] = '\0';
        }
    }

    return result;
}
