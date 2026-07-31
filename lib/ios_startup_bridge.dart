import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const MethodChannel iosStartupChannel = MethodChannel('byb/startup');
bool _didNotifyGraphTemplateReady = false;
bool _graphTemplateMounted = false;
bool _didReceiveIosGpuFrame = false;
bool _didReceiveIosUIKitReady = false;
Completer<void>? _graphPaintReadyCompleter;
Completer<void>? _iosGpuFrameWaiter;
Completer<void>? _iosUIKitReadyWaiter;
VoidCallback? _onIosUiPaintReadyForAccessory;

bool get isIosGraphTemplateStartupReady => _didNotifyGraphTemplateReady;

void registerIosUiPaintReadyForAccessoryCallback(VoidCallback callback) {
  _onIosUiPaintReadyForAccessory = callback;
}

void installIosStartupChannelHandler() {
  if (kIsWeb || !Platform.isIOS) {
    return;
  }
  iosStartupChannel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'scheduleFrame':
        nudgeIosDartFrameScheduling();
        return null;
      case 'onUIKitReady':
        final reason = (call.arguments as Map<Object?, Object?>?)?['reason'];
        debugPrint(
          'BYB DART onUIKitReady reason=$reason lifecycle=${WidgetsBinding.instance.lifecycleState}',
        );
        if (_didReceiveIosUIKitReady) {
          return null;
        }
        _didReceiveIosUIKitReady = true;
        final uiKitWaiter = _iosUIKitReadyWaiter;
        _iosUIKitReadyWaiter = null;
        if (uiKitWaiter != null && !uiKitWaiter.isCompleted) {
          uiKitWaiter.complete();
        }
        forceIosDartLifecycleResumedForColdLaunch();
        unawaited(completeIosGraphStartupIfReady());
        return null;
      case 'onBecameActive':
        nudgeIosDartFrameScheduling();
        unawaited(completeIosGraphStartupIfReady());
        return null;
      case 'presentationComplete':
        debugPrint('BYB DART native presentation complete');
        nudgeIosDartFrameScheduling();
        return null;
      case 'gpuFramePresented':
        _didReceiveIosGpuFrame = true;
        final count = (call.arguments as Map<Object?, Object?>?)?['count'];
        debugPrint('BYB DART native GPU frame presented count=$count');
        final waiter = _iosGpuFrameWaiter;
        _iosGpuFrameWaiter = null;
        if (waiter != null && !waiter.isCompleted) {
          waiter.complete();
        }
        unawaited(completeIosGraphStartupIfReady());
        return null;
      default:
        throw MissingPluginException('No handler for ${call.method}');
    }
  });
}

bool get didReceiveIosGpuFrame => _didReceiveIosGpuFrame;

bool get didReceiveIosUIKitReady => _didReceiveIosUIKitReady;

void resetIosStartupBridgeForNewLaunch() {
  if (kIsWeb || !Platform.isIOS) return;
  _didReceiveIosUIKitReady = false;
  _didReceiveIosGpuFrame = false;
  _didNotifyGraphTemplateReady = false;
  _graphTemplateMounted = false;
}

Future<void> notifyDartStartupListening() async {
  if (kIsWeb || !Platform.isIOS) return;
  installIosStartupChannelHandler();
  try {
    await iosStartupChannel.invokeMethod('dartStartupListening');
    debugPrint('BYB DART dartStartupListening acknowledged');
  } catch (e) {
    debugPrint('BYB DART dartStartupListening failed: $e');
  }
}

Future<void> waitForNativeIosUIKitReady({
  Duration timeout = const Duration(seconds: 5),
}) async {
  if (kIsWeb || !Platform.isIOS) return;
  if (_didReceiveIosUIKitReady) {
    debugPrint('BYB DART UIKit ready already received');
    return;
  }
  installIosStartupChannelHandler();
  _iosUIKitReadyWaiter = Completer<void>();
  await notifyDartStartupListening();
  if (_didReceiveIosUIKitReady) {
    debugPrint('BYB DART UIKit ready wait satisfied (during notify)');
    return;
  }
  try {
    await _iosUIKitReadyWaiter!.future.timeout(timeout);
    debugPrint('BYB DART UIKit ready wait satisfied');
  } on TimeoutException {
    debugPrint(
      'BYB DART UIKit ready wait timed out after ${timeout.inMilliseconds}ms',
    );
  } finally {
    if (_iosUIKitReadyWaiter != null && !_iosUIKitReadyWaiter!.isCompleted) {
      _iosUIKitReadyWaiter!.complete();
    }
    _iosUIKitReadyWaiter = null;
  }
}

Future<void> notifyNativeDartFrameScheduled() async {
  if (kIsWeb || !Platform.isIOS) return;
  try {
    await iosStartupChannel.invokeMethod('dartFrameScheduled');
    debugPrint('BYB DART dartFrameScheduled acknowledged');
  } catch (e) {
    debugPrint('BYB DART dartFrameScheduled failed: $e');
  }
}

Future<void> notifyNativeSurfaceRecycle() async {
  if (kIsWeb || !Platform.isIOS) return;
  try {
    await iosStartupChannel.invokeMethod('requestSurfaceRecycle');
    debugPrint('BYB DART requestSurfaceRecycle acknowledged');
  } catch (e) {
    debugPrint('BYB DART requestSurfaceRecycle failed: $e');
  }
}

Future<bool> waitForIosNativeGpuFrame({
  Duration timeout = const Duration(seconds: 8),
}) async {
  if (kIsWeb || !Platform.isIOS) return true;
  if (_didReceiveIosGpuFrame) return true;
  installIosStartupChannelHandler();
  _iosGpuFrameWaiter = Completer<void>();
  try {
    await _iosGpuFrameWaiter!.future.timeout(timeout);
    debugPrint('BYB DART GPU frame wait satisfied');
    return _didReceiveIosGpuFrame;
  } on TimeoutException {
    debugPrint(
      'BYB DART GPU frame wait timed out after ${timeout.inMilliseconds}ms',
    );
    return false;
  } finally {
    if (_iosGpuFrameWaiter != null && !_iosGpuFrameWaiter!.isCompleted) {
      _iosGpuFrameWaiter!.complete();
    }
    _iosGpuFrameWaiter = null;
  }
}

Future<void> notifyNativeFirstFrameReady(String phase) async {
  if (kIsWeb) return;
  installIosStartupChannelHandler();
  for (var attempt = 0; attempt < 8; attempt++) {
    try {
      await iosStartupChannel.invokeMethod('firstFrameReady', {
        'phase': phase,
      });
      return;
    } catch (e) {
      if (attempt == 7) {
        debugPrint('BYB startup channel invoke failed ($phase): $e');
        return;
      }
      await Future<void>.delayed(Duration(milliseconds: 80 * (attempt + 1)));
    }
  }
}

void nudgeIosDartFrameScheduling() {
  if (kIsWeb || !Platform.isIOS) return;
  if (!SchedulerBinding.instance.hasScheduledFrame) {
    SchedulerBinding.instance.scheduleFrame();
  }
}

/// Native confirms UIApplication is active before this runs.
void forceIosDartLifecycleResumedForColdLaunch() {
  if (kIsWeb || !Platform.isIOS) return;
  final binding = WidgetsBinding.instance;
  final state = binding.lifecycleState;
  if (state == AppLifecycleState.resumed) {
    nudgeIosDartFrameScheduling();
    return;
  }
  debugPrint('BYB DART force lifecycle resume from $state');
  binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  SchedulerBinding.instance.scheduleFrame();
}

void markIosGraphTemplateMounted() {
  if (kIsWeb || !Platform.isIOS) return;
  _graphTemplateMounted = true;
  unawaited(completeIosGraphStartupIfReady());
}

Future<void> completeIosGraphStartupIfReady() async {
  if (kIsWeb || !Platform.isIOS) return;
  if (_didNotifyGraphTemplateReady) return;
  if (!_graphTemplateMounted) return;
  if (!_didReceiveIosUIKitReady) return;
  if (!_didReceiveIosGpuFrame) return;
  if (_graphPaintReadyCompleter != null) {
    return _graphPaintReadyCompleter!.future;
  }

  _graphPaintReadyCompleter = Completer<void>();
  installIosStartupChannelHandler();

  try {
    nudgeIosDartFrameScheduling();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    _didNotifyGraphTemplateReady = true;
    debugPrint('BYB DART graph paint ready release=${!kDebugMode}');
    await notifyNativeFirstFrameReady('graph_template');
    _onIosUiPaintReadyForAccessory?.call();
    _graphPaintReadyCompleter!.complete();
  } catch (e, st) {
    _didNotifyGraphTemplateReady = false;
    debugPrint('BYB DART graph startup failed: $e\n$st');
    if (_graphPaintReadyCompleter != null &&
        !_graphPaintReadyCompleter!.isCompleted) {
      _graphPaintReadyCompleter!.completeError(e, st);
    }
  } finally {
    if (_graphPaintReadyCompleter != null &&
        !_graphPaintReadyCompleter!.isCompleted) {
      _graphPaintReadyCompleter!.complete();
    }
    _graphPaintReadyCompleter = null;
  }
}

@Deprecated('Use markIosGraphTemplateMounted + completeIosGraphStartupIfReady')
Future<void> notifyIosGraphTemplatePaintReady() => completeIosGraphStartupIfReady();

Future<void> retryIosGraphTemplatePaintReadyIfNeeded() =>
    completeIosGraphStartupIfReady();

void startIosColdLaunchRepaintBurst() {}

void disposeIosColdLaunchRepaintBurst() {}
