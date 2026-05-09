import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'app_shell.dart' deferred as app_shell;

const MethodChannel _startupChannel = MethodChannel('byb/startup');

/// iOS keeps `UILaunchStoryboardName` until Flutter’s **first raster frame**. This file must stay
/// tiny (SDK imports + deferred `app_shell`) so that frame compiles and paints before the heavy
/// app graph is loaded from the deferred part.
Future<void> main() async {
  // WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  
  if (kIsWeb) {
    await app_shell.loadLibrary();
    app_shell.registerDeferredStartupTasks();
    runApp(app_shell.buildRootApp());
    return;
  }

  runApp(const _IosFastFirstFrame());
}

class _IosFastFirstFrame extends StatefulWidget {
  const _IosFastFirstFrame();

  @override
  State<_IosFastFirstFrame> createState() => _IosFastFirstFrameState();
}

class _IosFastFirstFrameState extends State<_IosFastFirstFrame> {
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('BYB DART FIRST FRAME (bootstrap)');
      _notifyNativeFirstFrameReady('bootstrap');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _mountFullApp());
  }

  Future<void> _notifyNativeFirstFrameReady(String phase) async {
    if (kIsWeb) return;
    try {
      debugPrint('BYB startup channel send begin ($phase)');
      await _startupChannel
          .invokeMethod('firstFrameReady', {'phase': phase})
          .timeout(const Duration(seconds: 2));
      debugPrint('BYB startup channel send success ($phase)');
    } catch (e) {
      debugPrint('BYB startup channel invoke failed ($phase): $e');
    }
  }

  Future<void> _mountFullApp() async {
    await app_shell.loadLibrary();
    app_shell.registerDeferredStartupTasks();
    if (!mounted) return;
    setState(() {
      _isReady = true;
      // FlutterNativeSplash.remove();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isReady) {
      return app_shell.buildRootApp();
    }
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
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
