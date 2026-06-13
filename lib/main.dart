import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'ios_startup_bridge.dart';
import 'app_shell.dart' deferred as app_shell;
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  resetIosStartupBridgeForNewLaunch();
  installIosStartupChannelHandler();

  if (kIsWeb) {
    await app_shell.loadLibrary();
    app_shell.registerDeferredStartupTasks();
    runApp(app_shell.buildRootApp());
    return;
  } else
  if (Platform.isIOS) {
    await waitForNativeIosUIKitReady(timeout: const Duration(seconds: 5));
    runApp(const _IosMetalBootstrap());
    return;
  } else
  if (Platform.isWindows || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = WindowOptions(
      size: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    await app_shell.loadLibrary();
    await app_shell.preloadGraphModule();
    app_shell.registerDeferredStartupTasks();
    runApp(app_shell.buildRootApp());
    return;
  }

  await app_shell.loadLibrary();
  await app_shell.preloadGraphModule();
  app_shell.registerDeferredStartupTasks();
  runApp(app_shell.buildRootApp());
}

/// Mount a trivial tree first so Metal can present before [GraphTemplate] loads.
class _IosMetalBootstrap extends StatefulWidget {
  const _IosMetalBootstrap();

  @override
  State<_IosMetalBootstrap> createState() => _IosMetalBootstrapState();
}

class _IosMetalBootstrapState extends State<_IosMetalBootstrap> {
  bool _showFullApp = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_warmMetalThenMountFullApp());
    });
  }

  Future<void> _waitForFrames(int count) async {
    for (var i = 0; i < count; i++) {
      final gate = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!gate.isCompleted) gate.complete();
      });
      nudgeIosDartFrameScheduling();
      await gate.future;
    }
  }

  Future<void> _warmMetalThenMountFullApp() async {
    forceIosDartLifecycleResumedForColdLaunch();
    await _waitForFrames(2);
    if (!mounted) return;

    await notifyNativeDartFrameScheduled();
    await notifyNativeFirstFrameReady('bootstrap');
    nudgeIosDartFrameScheduling();
    await _waitForFrames(1);

    var gotGpu = await waitForIosNativeGpuFrame(
      timeout: const Duration(seconds: 8),
    );
    if (!gotGpu) {
      debugPrint('BYB DART bootstrap GPU wait timed out — recycling surface');
      await notifyNativeSurfaceRecycle();
      nudgeIosDartFrameScheduling();
      await _waitForFrames(2);
      gotGpu = await waitForIosNativeGpuFrame(
        timeout: const Duration(seconds: 8),
      );
    }
    debugPrint('BYB DART bootstrap GPU ready=$gotGpu');

    await app_shell.loadLibrary();
    app_shell.registerDeferredStartupTasks();
    if (!mounted) return;
    setState(() {
      _showFullApp = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showFullApp) {
      return app_shell.buildRootApp();
    }
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFF222222),
        body: Center(
          child: Text(
            'Starting Spike Recorder…',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ),
    );
  }
}
