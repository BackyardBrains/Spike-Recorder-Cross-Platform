#import <Flutter/Flutter.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

void BYBEnsureFlutterSurfaceVisible(FlutterViewController *controller, NSString *reason);

void BYBRecycleFlutterSurface(FlutterViewController *controller, NSString *reason);

void BYBKickstartFlutterRendering(FlutterViewController *controller, NSString *reason);

/// MFi cold launch can start the implicit engine while UIApplication is still backgrounded,
/// leaving isGpuDisabled=YES. willEnterForeground may never fire; didBecomeActive must re-enable.
void BYBEnableFlutterGpuAndResume(FlutterViewController *controller, NSString *reason);

NS_ASSUME_NONNULL_END
