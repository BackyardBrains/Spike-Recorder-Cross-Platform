import 'dart:async';

import 'package:byb_accessory/byb_accessory.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'package:firebase_crashlytics/firebase_crashlytics.dart';
// import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:spikerbox_architecture/provider/custom_slider_provider.dart';
import 'package:spikerbox_architecture/provider/fft_status_provider.dart';
import 'package:spikerbox_architecture/provider/threshold_status_provider.dart';
import 'package:spikerbox_architecture/screen/page_route_screen.dart';
import 'firebase_options.dart';
import 'provider/provider_export.dart';
import 'screen/graph_template.dart' deferred as deferred_graph;

enum Command {
  start,
  stop,
  change,
}

int screenWidth = 0;
const MethodChannel _startupChannel = MethodChannel('byb/startup');

Future<void> notifyNativeFirstFrameReady(String phase) async {
  if (kIsWeb) return;
  try {
    await _startupChannel.invokeMethod('firstFrameReady', {'phase': phase});
  } catch (e) {
    debugPrint('BYB startup channel invoke failed ($phase): $e');
  }
}

/// Full app root (providers + [MyApp]). Loaded from a **deferred** library so iOS can raster a
/// tiny [main.dart] frame first and dismiss the system launch storyboard.
Widget buildRootApp() {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ConstantProvider()),
      ChangeNotifierProvider(create: (_) => GraphDataProvider()),
      ChangeNotifierProvider(create: (_) => VerticalDragProvider()),
      ChangeNotifierProvider(create: (_) => GraphGainProvider()),
      ChangeNotifierProvider(create: (_) => GraphResumePlayProvider()),
      ChangeNotifierProvider(create: (_) => DataStatusProvider()),
      ChangeNotifierProvider(create: (_) => SoftwareConfigProvider()),
      ChangeNotifierProvider(create: (_) => SerialDataProvider()),
      ChangeNotifierProvider(create: (_) => PortScanProvider()),
      ChangeNotifierProvider(create: (_) => SampleRateProvider()),
      ChangeNotifierProvider(create: (_) => ChannelColorProvider()),
      ChangeNotifierProvider(create: (_) => ChannelFilterProvider()),
      ChangeNotifierProvider(create: (_) => CustomRangeSliderProvider()),
      ChangeNotifierProvider(create: (_) => FftStatusProvider()),
      ChangeNotifierProvider(create: (_) => ThresholdStatusProvider()),
    ],
    child: const MyApp(),
  );
}

void registerDeferredStartupTasks() {
  Future.delayed(const Duration(milliseconds: 200), () async {
    unawaited(_initializeFirebaseAndCrashlytics());
  });
}

Future<void> _initializeFirebaseAndCrashlytics() async {
  try {
    // await Firebase.initializeApp(
    //   options: DefaultFirebaseOptions.currentPlatform,
    // );
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
    return;
  }

  if (kIsWeb) return;
  // FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  // PlatformDispatcher.instance.onError = (error, stack) {
  //   FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  //   return true;
  // };
}

class MyApp extends StatefulWidget {
  // static FirebaseAnalytics analytics = FirebaseAnalytics.instance;

  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  String platForm = '';
  late int sumResult;
  late Future<int> sumAsyncResult;
  final number = ValueNotifier(0);
  bool _didLogFirstFrame = false;
  bool _didStartAccessoryInit = false;
  Timer? _accessoryInitRetryTimer;
  int _iosHomeEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [],
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startAccessoryInitIfNeeded();
        // if (SchedulerBinding.instance.hasScheduledFrame) return;
        SchedulerBinding.instance.scheduleFrame();
      });
      /*
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted) {
            setState(() {});
          }
        });
      });
      _armAccessoryInitRetryLoop();
      */
      // Accessory cold launch can complete first-frame callbacks while UI composition stays stale.
      // Force one remount shortly after startup to guarantee GraphTemplate paints.
      // Future.delayed(const Duration(milliseconds: 900), () {
      Future.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        if (SchedulerBinding.instance.hasScheduledFrame) return;
        SchedulerBinding.instance.scheduleFrame();

        setState(() {
          // _iosHomeEpoch++;
        });
      });
    }
  }

  @override
  void dispose() {
    _accessoryInitRetryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kIsWeb && state == AppLifecycleState.resumed) {
      _startAccessoryInitIfNeeded();
      setState(() {
        // _iosHomeEpoch++;
      });
    }
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  void _startAccessoryInitIfNeeded() {
    if (_didStartAccessoryInit || kIsWeb) return;
    final state = WidgetsBinding.instance.lifecycleState;
    debugPrint('BYB accessory init gate lifecycleState=$state');
    // Accessory cold-launch can bounce through transient states; only skip if detached.
    if (state != null && state == AppLifecycleState.detached) {
      debugPrint('BYB accessory init deferred (detached)');
      return;
    }
    _didStartAccessoryInit = true;
    _accessoryInitRetryTimer?.cancel();
    debugPrint('BYB accessory init launching now');
    unawaited(_initAccessoryProtocol());
  }

  void _armAccessoryInitRetryLoop() {
    if (kIsWeb) return;
    _accessoryInitRetryTimer?.cancel();
    _accessoryInitRetryTimer =
        Timer.periodic(const Duration(milliseconds: 400), (timer) {
      if (!mounted || _didStartAccessoryInit) {
        timer.cancel();
        return;
      }
      _startAccessoryInitIfNeeded();
    });
  }

  Future<void> _initAccessoryProtocol() async {
    try {
      debugPrint('BYB iOS MFi init protocol starting...');
      await BybAccessory.initWithProtocol('com.backyardbrains.spikerbox');
      debugPrint('BYB iOS MFi init protocol finished.');
    } catch (e, st) {
      debugPrint('BYB MFi init failed: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && !_didStartAccessoryInit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startAccessoryInitIfNeeded();
      });
    }
    if (!_didLogFirstFrame) {
      _didLogFirstFrame = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint('BYB DART FIRST FRAME (app_shell)');
        unawaited(notifyNativeFirstFrameReady('app_shell'));
      });
    }
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Spike Recorder',
        theme: ThemeData(
          // brightness: Brightness.dark,
          primarySwatch: Colors.blue,
          // scaffoldBackgroundColor: Colors.black,
          // canvasColor: Colors.black,
          textTheme: const TextTheme(),
        ),
        home: kIsWeb
            ? const DashBoardPageRoute()
            : KeyedSubtree(
                key: ValueKey('ios-home-$_iosHomeEpoch'),
                child: const _MobileDeferredGraphHome(),
              ));
  }
}

class _MobileDeferredGraphHome extends StatefulWidget {
  const _MobileDeferredGraphHome();

  @override
  State<_MobileDeferredGraphHome> createState() =>
      _MobileDeferredGraphHomeState();
}

class _MobileDeferredGraphHomeState extends State<_MobileDeferredGraphHome> {
  late final Future<void> _libraryLoaded = deferred_graph.loadLibrary();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _libraryLoaded,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint(
              'BYB deferred_graph load failed: ${snapshot.error}\n${snapshot.stackTrace}');
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(
              child: Text(
                'Could not load app module.\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StartupPlaceholder();
        }

        return Consumer<ConstantProvider>(
          builder: (context, data, _) {
            return deferred_graph.GraphTemplate(
              channelCount: data.getChannelCount(),
              bitsData: data.getBitData(),
              baudRate: data.getBaudRate(),
            );
          },
        );
      },
    );
  }
}

class _StartupPlaceholder extends StatelessWidget {
  const _StartupPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: CircularProgressIndicator(),
        // child: Text(
        //   'Starting Spike Recorder...',
        //   style: TextStyle(color: Colors.white, fontSize: 16),
        // ),
      ),
    );
  }
}
