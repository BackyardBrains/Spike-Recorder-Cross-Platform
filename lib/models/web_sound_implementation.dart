// // import 'dart:async';
// // import 'dart:typed_data';

// // import 'package:flutter/material.dart';

// // import 'package:just_audio/just_audio.dart';
// // import 'package:microphone/microphone.dart';

// // /// Example app demonstrating how to use the `microphone` plugin and with that
// // /// a [MicrophoneRecorder].
// // ///
// // /// The example app listens to realtime updates of the recording and based on
// // /// that provides functionality to start, stop, and listen to a recording.
// // class MicrophoneExampleApp extends StatefulWidget {
// //   /// Constructs [MicrophoneExampleApp].
// //   const MicrophoneExampleApp({Key? key}) : super(key: key);

// //   @override
// //   _MicrophoneExampleAppState createState() => _MicrophoneExampleAppState();
// // }

// // class _MicrophoneExampleAppState extends State<MicrophoneExampleApp> {
// //   MicrophoneRecorder? _recorder;
// //   AudioPlayer? _audioPlayer;
// //   StreamController<Uint8List> addListenAudioStream = StreamController();

// //   @override
// //   void initState() {
// //     super.initState();

// //     _initRecorder();
// //     listenEvent();
// //   }

// //   @override
// //   void dispose() {
// //     _recorder?.dispose();
// //     _audioPlayer?.dispose();

// //     super.dispose();
// //   }

// //   void listenEvent() {
// //     micStream.listen((event) {
// //       print("the event is $event");
// //     });
// //   }

// //   late final Stream<Uint8List> micStream;

// //   void _initRecorder() {
// //     micStream = addListenAudioStream.stream.asBroadcastStream();
// //     // Dispose the previous recorder.
// //     _recorder?.dispose();

// //     _recorder = MicrophoneRecorder()
// //       ..init()
// //       ..addListener(() async {
// //         final byteAdded = await _recorder?.toBytes();
// //         addListenAudioStream.add(byteAdded!);
// //         setState(() {});
// //       });
// //   }

// //   @override
// //   Widget build(BuildContext context) {
// //     final value = _recorder!.value;

// //     Widget result;

// //     if (value.started) {
// //       if (value.stopped) {
// //         result = Column(
// //           mainAxisAlignment: MainAxisAlignment.center,
// //           children: [
// //             OutlinedButton(
// //               onPressed: () {
// //                 setState(_initRecorder);
// //               },
// //               child: Text('Restart recorder'),
// //             ),
// //             Padding(
// //               padding: const EdgeInsets.only(
// //                 top: 16,
// //               ),
// //               child: OutlinedButton(
// //                 onPressed: () async {
// //                   _audioPlayer?.dispose();

// //                   _audioPlayer = AudioPlayer();

// //                   await _audioPlayer?.setUrl(value.recording!.url);
// //                   await _audioPlayer!.play();
// //                 },
// //                 child: Text('Play recording'),
// //               ),
// //             ),
// //           ],
// //         );
// //       } else {
// //         result = OutlinedButton(
// //           onPressed: () {
// //             _recorder!.stop();
// //           },
// //           child: Text('Stop recording'),
// //         );
// //       }
// //     } else {
// //       result = OutlinedButton(
// //         onPressed: () {
// //           _recorder!.start();

// //           _recorder?.toBytes().asStream().listen((event) {
// //             print("the event is $event");
// //           });
// //         },
// //         child: Text('Start recording'),
// //       );
// //     }

// //     return MaterialApp(
// //       home: Scaffold(
// //         body: Center(
// //           child: result,
// //         ),
// //       ),
// //     );
// //   }
// // }

// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'dart:js' as js;

// class ListenInWeb extends StatefulWidget {
//   const ListenInWeb({super.key});

//   @override
//   State<ListenInWeb> createState() => _ListenInWebState();
// }

// class _ListenInWebState extends State<ListenInWeb> {
//   int isOpeningFile = 0;

//   String versionNumber = '1.2.1';

//   int _counter = 0;

//   int extraChannels = 0;
//   int minChannels = 0;
//   int maxChannels = 0;

//   int localChannel = 1;

//   double prevY = 0.0;

//   List<double> channelGains = [10000, 10000, 10000, 10000, 10000, 10000];

//   int minIndexSerial = 1;
//   int maxIndexSerial = 25;

//   int minIndexHid = 1;
//   int maxIndexHid = 15;

//   int minIndexAudio = 1;
//   int maxIndexAudio = 20;

//   List<double> listIndexSerial = [5, 5, 5, 5, 5, 5];
//   List<double> listIndexHid = [7, 7, 7, 7, 7, 7];
//   List<double> listIndexAudio = [9, 9];

//   List<double> levelMedian = [-1, -1, -1, -1, -1, -1];
//   List<double> initialLevelMedian = [0, 0, 0, 0, 0, 0];

//   List<double> chartData = [];
//   List<List<double>> channelsData = [];

//   var horizontalDiff = 0;

//   num timeScale = 10000; //10ms to 10 seconds
//   num curTimeScaleBar = 1000; //10ms to 10 seconds
//   num curSkipCounts = 256;
//   num curFps = 30;
//   int sampleRate = 44100;
//   List<double> arrDataMax = []; //10 seconds
//   List<double> arrData = []; // current

//   int capacity = 1;
//   int capacityMin = 1;
//   int capacityMax = 1;

//   int isPlaying = 0;
//   int isRecording = 0;
//   int deviceType = 0; // 0 - audio | 1 - serial

//   callbackIsOpeningWavFile(params) {
//     isOpeningFile = params[0];
//     setState(() {});
//   }

//   var settingParams = {
//     "channelCount": -1,
//     "maxAudioChannels": 2,
//     "maxSerialChannels": 6,
//     "initialMaxSerialChannels": 6,
//     "muteSpeakers": true,
//     "lowFilterValue": "0",
//     "highFilterValue": "1000",
//     "notchFilter50": false,
//     "notchFilter60": false,
//     "defaultMicrophoneLeftColor": 0,
//     "defaultMicrophoneRightColor": 1,
//     "defaultSerialColor1": 0,
//     "defaultSerialColor2": 1,
//     "defaultSerialColor3": 2,
//     "defaultSerialColor4": 3,
//     "defaultSerialColor5": 4,
//     "defaultSerialColor6": 5,
//     "flagDisplay1": 1,
//     "flagDisplay2": 0,
//     "flagDisplay3": 0,
//     "flagDisplay4": 0,
//     "flagDisplay5": 0,
//     "flagDisplay6": 0,
//     "strokeWidth": 1.25,
//     "strokeOptions": [1, 1.25, 1.5, 1.75, 2],
//     "enableDeviceLegacy": false
//   };

//   callbackAudioInit(params) {
//     deviceType = params[0];
//     isPlaying = params[1];
//     // startRecordingTime = (DateTime.now());
//     channelGains = [10000, 10000, 10000, 10000, 10000, 10000];
//     listIndexSerial = [5, 5, 5, 5, 5, 5];
//     listIndexHid = [7, 7, 7, 7, 7, 7];
//     listIndexAudio = [9, 9];

//     settingParams["flagDisplay1"] = 1;
//     settingParams["flagDisplay2"] = 0;
//     settingParams["defaultMicrophoneLeftColor"] = 0;
//     settingParams["defaultMicrophoneRightColor"] = 1;
//     // channelsColor[0] = audioChannelColors[0];
//     // channelsColor[1] = audioChannelColors[1];
//     // print("channelsColor[0] : "+channelsColor[0].toString());
//     // print("channelsColor[1] : "+channelsColor[1].toString());

//     js.context.callMethod('setFlagChannelDisplay', [
//       settingParams["flagDisplay1"],
//       settingParams["flagDisplay2"],
//       settingParams["flagDisplay3"],
//       settingParams["flagDisplay4"],
//       settingParams["flagDisplay5"],
//       settingParams["flagDisplay6"]
//     ]);
//     // if (initFPS){
//     //   initFPS = false;
//     //   Fps.instance.start();
//     //   Fps.instance.addFpsCallback((FpsInfo fpsInfo) async {
//     //     // print("fpsInfo.fps");
//     //     // print(fpsInfo.fps);
//     //     if (curFps == fpsInfo.fps){
//     //       return;
//     //     }
//     //     curFps = fpsInfo.fps;
//     //     int incSkip = 0;
//     //     if (curFps < 30){

//     //     }else
//     //     if (curFps <15){
//     //       incSkip++;
//     //     }

//     //     // if (curFps <15){
//     //     //   incSkip++;
//     //     // }
//     //     if (!isFeedback)
//     //       ( await js.context.callMethod('setFps', [ curFps, incSkip ]) );
//     //   });

//     // }

//     setState(() {});
//   }

//   @override
//   void initState() {
//     // TODO: implement initState
//     super.initState();
//     js.context['callbackAudioInit'] = callbackAudioInit;
//     js.context['callbackIsOpeningWavFile'] = callbackIsOpeningWavFile;
//     Future.delayed(const Duration(seconds: 2), () {
//       isPlaying = 1;
//       js.context
//           .callMethod('recordAudio', ['Flutter is calling upon JavaScript!']);
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold();
//   }
// }
