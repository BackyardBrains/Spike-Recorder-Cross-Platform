import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:spikerbox_architecture/provider/custom_slider_provider.dart';
import 'package:spikerbox_architecture/provider/fft_status_provider.dart';
import 'package:spikerbox_architecture/provider/threshold_status_provider.dart';
import 'package:spikerbox_architecture/screen/page_route_screen.dart';
import 'firebase_options.dart';
import 'provider/provider_export.dart';
import 'screen/graph_template.dart';

enum Command {
  start,
  stop,
  change,
}

int screenWidth = 0;
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    print('Firebase initialization error: $e');
    // Continue without Firebase on web if it fails
  }

  // Pass all uncaught "fatal" errors from the framework to Crashlytics
  // Note: Crashlytics is not supported on web
  if (!kIsWeb) {
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }
  // Future.delayed(Duration(seconds: 7), () {
  //   throw Exception('Test Crash');
  // });

  runApp(
    MultiProvider(
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
    ),
  );
}

class MyApp extends StatefulWidget {
  static FirebaseAnalytics analytics = FirebaseAnalytics.instance;

  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // late JavascriptRuntime jsRunTime = getJavascriptRuntime();

  String platForm = '';
  late int sumResult;
  late Future<int> sumAsyncResult;
  final number = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky,
        overlays: []);
    // SchedulerBinding.instance.addTimingsCallback((timings) async {
    //   await requestToMic();
    // });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Spike Recorder Web Demo',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          textTheme: const TextTheme(

              // for the body2 text
              // You can add other text styles here as needed
              ),
        ),
        home: kIsWeb
            ? const DashBoardPageRoute()
            // HomePage()
            : Consumer<ConstantProvider>(
                builder: (context, data, child) {
                  return GraphTemplate(
                    channelCount: data.getChannelCount(),
                    bitsData: data.getBitData(),
                    baudRate: data.getBaudRate(),
                  );
                },
              ));
  }
}
