/*************************************************************************/
/*  godot_render_watchdog.mm                                             */
/*************************************************************************/

// Restarts Godot's render loop if it stays stopped while the app is visibly
// active.
//
// Godot (drivers/apple_embedded) stops its CADisplayLink in on_focus_out()
// (sceneWillResignActive) and restarts it in on_focus_in()
// (sceneDidBecomeActive), both guarded by a single is_focused flag. The whole
// engine start-up (Main::setup2 / Main::start, removal of the launch-screen
// overlay) runs inside that display link. If a system alert (notification
// permission) or the Game Center sheet interrupts the start and the matching
// "did become active" callback never reaches Godot -- or arrives before the
// "will resign active" one -- the display link is never restarted and the app
// hangs on the launch screen forever. That is what App Review saw on
// iPadOS 27 (iPad Air M3, iPhone app in compatibility mode, fresh install).
//
// Instead of trusting the event order, this polls the real state: if the Godot
// view is on screen, its scene is foreground-active for two consecutive ticks,
// and the view is still not rendering, it replays Godot's own focus-in path and
// starts rendering again. Both calls are no-ops when Godot is already fine.

#import <UIKit/UIKit.h>

#import "drivers/apple_embedded/app_delegate_service.h"
#import "drivers/apple_embedded/godot_app_delegate.h"
#import "drivers/apple_embedded/godot_view_apple_embedded.h"
#import "drivers/apple_embedded/godot_view_controller.h"

static const NSTimeInterval kWatchdogInterval = 0.5;

@interface GodotRenderWatchdog : NSObject
@end

@implementation GodotRenderWatchdog {
	NSTimer *_timer;
	int _stalledTicks;
}

+ (void)load {
	[[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
													  object:nil
													   queue:[NSOperationQueue mainQueue]
												  usingBlock:^(NSNotification *_Nonnull note) {
													  [[GodotRenderWatchdog shared] start];
												  }];
}

+ (instancetype)shared {
	static GodotRenderWatchdog *sharedInstance = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedInstance = [[GodotRenderWatchdog alloc] init];
	});
	return sharedInstance;
}

- (void)start {
	if (_timer) {
		return;
	}
	_timer = [NSTimer timerWithTimeInterval:kWatchdogInterval target:self selector:@selector(tick:) userInfo:nil repeats:YES];
	[[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (BOOL)isForegroundActive:(UIView *)view {
	UIWindowScene *scene = view.window.windowScene;
	if (scene) {
		return scene.activationState == UISceneActivationStateForegroundActive;
	}
	return UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
}

- (void)tick:(NSTimer *)timer {
	GDTView *view = GDTAppDelegateService.viewController.godotView;
	// Not created yet, deliberately off screen (e.g. covered by a full-screen
	// presentation) or already rendering: nothing to repair.
	if (!view || !view.window || view.isActive || ![self isForegroundActive:view]) {
		_stalledTicks = 0;
		return;
	}

	// Require the stall to persist for a second tick so a regular, still
	// in-flight activation transition is never overridden.
	_stalledTicks++;
	if (_stalledTicks < 2) {
		return;
	}
	_stalledTicks = 0;

	NSLog(@"GodotRenderWatchdog: scene is active but Godot is not rendering -- restarting render loop.");

	// Godot's own focus-in path (OS_AppleEmbedded::on_focus_in: window focus
	// event, NOTIFICATION_APPLICATION_FOCUS_IN, audio restart). Guarded by
	// is_focused inside Godot, so harmless if it already ran.
	UIScene *scene = view.window.windowScene;
	for (GDTAppDelegateServiceProtocol *service in GDTApplicationDelegate.services) {
		if ([service isKindOfClass:[GDTAppDelegateService class]] && scene && [service respondsToSelector:@selector(sceneDidBecomeActive:)]) {
			[service sceneDidBecomeActive:scene];
		}
	}

	// on_focus_in() is skipped when Godot already believes it is focused while
	// the display link is stopped -- start it directly (no-op if running).
	[view startRendering];
}

@end
