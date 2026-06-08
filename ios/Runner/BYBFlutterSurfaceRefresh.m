#import "BYBFlutterSurfaceRefresh.h"

#import <objc/message.h>

static void BYBInvokeSurfaceUpdated(FlutterViewController *controller, BOOL appeared) {
  SEL selector = NSSelectorFromString(@"surfaceUpdated:");
  if (![controller respondsToSelector:selector]) {
    return;
  }
  void (*surfaceUpdated)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))objc_msgSend;
  surfaceUpdated(controller, selector, appeared);
}

static void BYBAppearanceTransitionRecycle(FlutterViewController *controller) {
  [controller beginAppearanceTransition:NO animated:NO];
  [controller endAppearanceTransition];
  [controller beginAppearanceTransition:YES animated:NO];
  [controller endAppearanceTransition];
}

void BYBEnsureFlutterSurfaceVisible(FlutterViewController *controller, NSString *reason) {
  if (controller == nil) {
    NSLog(@"BYB ensureFlutterSurface skipped nil controller reason=%@", reason);
    return;
  }

  if (controller.isDisplayingFlutterUI) {
    NSLog(@"BYB ensureFlutterSurface skip (already displaying) reason=%@", reason);
    return;
  }

  BYBInvokeSurfaceUpdated(controller, YES);
  NSLog(@"BYB ensureFlutterSurface surfaceUpdated:YES reason=%@", reason);
}

void BYBRecycleFlutterSurface(FlutterViewController *controller, NSString *reason) {
  if (controller == nil) {
    NSLog(@"BYB recycleFlutterSurface skipped nil controller reason=%@", reason);
    return;
  }

  SEL selector = NSSelectorFromString(@"surfaceUpdated:");
  if ([controller respondsToSelector:selector]) {
    BYBInvokeSurfaceUpdated(controller, NO);
    BYBInvokeSurfaceUpdated(controller, YES);
    NSLog(@"BYB recycleFlutterSurface surfaceUpdated reason=%@", reason);
    return;
  }

  BYBAppearanceTransitionRecycle(controller);
  NSLog(@"BYB recycleFlutterSurface appearance-fallback reason=%@", reason);
}

void BYBEnableFlutterGpuAndResume(FlutterViewController *controller, NSString *reason) {
  if (controller == nil) {
    NSLog(@"BYB enableFlutterGpu skipped nil controller reason=%@", reason);
    return;
  }

  FlutterEngine *engine = controller.engine;
  if (engine == nil) {
    NSLog(@"BYB enableFlutterGpu skipped nil engine reason=%@", reason);
    return;
  }

  BOOL wasDisabled = engine.isGpuDisabled;
  engine.isGpuDisabled = NO;
  [engine.lifecycleChannel sendMessage:@"AppLifecycleState.resumed"];
  NSLog(
      @"BYB enableFlutterGpu wasDisabled=%@ nowDisabled=%@ reason=%@",
      wasDisabled ? @"YES" : @"NO",
      engine.isGpuDisabled ? @"YES" : @"NO",
      reason);
}

void BYBKickstartFlutterRendering(FlutterViewController *controller, NSString *reason) {
  if (controller == nil) {
    NSLog(@"BYB kickstartFlutterRendering skipped nil controller reason=%@", reason);
    return;
  }

  BYBEnableFlutterGpuAndResume(controller, reason);

  UIWindow *flutterWindow = controller.view.window;
  if (flutterWindow != nil) {
    flutterWindow.hidden = NO;
    [flutterWindow makeKeyAndVisible];
  }

  controller.view.hidden = NO;
  controller.view.alpha = 1.0;
  [controller.view setNeedsLayout];
  [controller.view layoutIfNeeded];

  BYBAppearanceTransitionRecycle(controller);
  BYBEnsureFlutterSurfaceVisible(
      controller, [NSString stringWithFormat:@"kickstart-%@", reason]);
  NSLog(@"BYB kickstartFlutterRendering reason=%@", reason);
}
