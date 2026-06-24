import 'dart:async';
import 'dart:io' show Platform;

import 'package:byb_accessory/byb_accessory.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'package:firebase_crashlytics/firebase_crashlytics.dart';
// import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:provider/provider.dart';
import 'package:spikerbox_architecture/provider/custom_slider_provider.dart';
import 'package:spikerbox_architecture/provider/fft_status_provider.dart';
import 'package:spikerbox_architecture/provider/threshold_status_provider.dart';
import 'package:spikerbox_architecture/constant/app_theme.dart';
import 'package:spikerbox_architecture/screen/page_route_screen.dart';
import 'firebase_options.dart';
import 'ios_startup_bridge.dart';
import 'provider/provider_export.dart';
import 'screen/graph_template.dart' deferred as deferred_graph;

enum Command {
  start,
  stop,
  change,
}

int screenWidth = 0;

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
      ChangeNotifierProvider(create: (_) => ThemeModeProvider()),
    ],
    child: const MyApp(),
  );
}

void registerDeferredStartupTasks() {
  Future.delayed(const Duration(milliseconds: 200), () async {
    unawaited(_initializeFirebaseAndCrashlytics());
  });
}

Future<void> preloadGraphModule() => deferred_graph.loadLibrary();

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
  bool _iosUiPaintReadyForAccessory = false;
  Timer? _accessoryInitRetryTimer;
  Timer? _iosAccessoryFallbackTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [],
      );
      if (Platform.isIOS) {
        // MFi protocol init must not wait for connector detection or first paint.
        _iosUiPaintReadyForAccessory = true;
        _startAccessoryInitIfNeeded();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(BybAccessory.logAccessoryDiagnostics());
        });
        registerIosUiPaintReadyForAccessoryCallback(() {
          _iosUiPaintReadyForAccessory = true;
          _startAccessoryInitIfNeeded();
        });
        _iosAccessoryFallbackTimer = Timer(const Duration(seconds: 2), () {
          if (!mounted || _didStartAccessoryInit) return;
          debugPrint('BYB iOS accessory init fallback');
          _startAccessoryInitIfNeeded();
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _startAccessoryInitIfNeeded();
          SchedulerBinding.instance.scheduleFrame();
        });
      }
      _armAccessoryInitRetryLoop();
    }
  }

  @override
  void dispose() {
    _accessoryInitRetryTimer?.cancel();
    _iosAccessoryFallbackTimer?.cancel();
    disposeIosColdLaunchRepaintBurst();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kIsWeb && state == AppLifecycleState.resumed) {
      _startAccessoryInitIfNeeded();
      if (!SchedulerBinding.instance.hasScheduledFrame) {
        SchedulerBinding.instance.scheduleFrame();
      }
      if (Platform.isIOS) {
        unawaited(completeIosGraphStartupIfReady());
      }
    }
  }

  void _startAccessoryInitIfNeeded() {
    if (_didStartAccessoryInit || kIsWeb) return;
    if (Platform.isIOS && !_iosUiPaintReadyForAccessory) {
      return;
    }
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
    return Consumer<ThemeModeProvider>(
      builder: (context, themeMode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Spike Recorder',
          theme: buildAppTheme(isDark: false),
          darkTheme: buildAppTheme(isDark: true),
          themeMode:
              themeMode.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: kIsWeb
              ? const DashBoardPageRoute()
              : const _MobileDeferredGraphHome(),
        );
      },
    );
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
    return Consumer<ThemeModeProvider>(
      builder: (context, themeMode, _) {
        return ColoredBox(
          color: AppThemeColors.of(themeMode.isDarkMode).graphBackground,
          child: const Center(
            child: CircularProgressIndicator(),
        // child: Text(
        //   'Starting Spike Recorder...',
        //   style: TextStyle(color: Colors.white, fontSize: 16),
        // ),
          ),
        );
      },
    );
  }
}
