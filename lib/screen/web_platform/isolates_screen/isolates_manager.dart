// import 'dart:async';
// import 'dart:convert';
// import 'dart:html';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:serial/serial.dart';
// import 'package:spikerbox_architecture/models/bit_wise_util.dart';
// import 'package:spikerbox_architecture/models/contants.dart';
// import '../../../dart_isolate_function/isolate_manager/isolate_manager_in_web.dart';
// import '../../../models/escape_sequences/escape_class.dart';
// import '../../../models/timing_util.dart';
// import '../../../models/usb_protocol/commands.dart';
// import 'isolate_sc_template.dart';

// class SerialPortWeb extends StatefulWidget {
//   const SerialPortWeb({Key? key}) : super(key: key);

//   @override
//   State<SerialPortWeb> createState() => _SerialPortWebState();
// }

// class _SerialPortWebState extends State<SerialPortWeb> {
//   bool toListenStream = true;
//   bool isListen = false;
//   IsolateManagerInWeb isolateManagerInWeb = IsolateManagerInWeb();
//   final StreamController<Uint8List> _streamControllerGraph = StreamController();
//   late Stream<Uint8List> _streamGraph;
//   SerialPort? _port;
//   SerialPortInfo? portInfo;

//   Future<void> _openPort() async {
//     final port = await window.navigator.serial.requestPort();
//     try {
//       await port.open(baudRate: kBaudRate, bufferSize: 8192);
//     } catch (e) {
//       print("Port opening failed: $e");
//     }
//     portInfo = port.getInfo();

//     _port = port;
//     setState(() {});
//   }

//   Future<void> _writeToPort() async {
//     if (_port == null) {
//       return;
//     }

//     final writer = _port!.writable.writer;

//     await writer.ready;
//     await writer.write(UsbCommand.hwVersionInquiry.cmdAsBytes());

//     await writer.ready;
//   }

//   Future<void> _readFromPort() async {
//     EscapeSequence escapdeinstance = EscapeSequence();
//     if (_port == null) {
//       return;
//     }
//     try {
//       final reader = _port!.readable.reader;
//       TimingUtil timingUtil = TimingUtil();

//       while (true) {
// //  if(isListen){

//         final ReadableStreamDefaultReadResult result = await reader.read();
//         // String message  = String.fromCharCodes(result.value);

//         //  if(message.contains(":")&& message.contains(";")){

//         // print("the upcoming print is event ${result.value}, as String: $message");

//          escapdeinstance.addPacket(result.value);

//         //  }
//         // timingUtil.addPacket(result.value);
//         // int dReceived = timingUtil.getTotalBytesReceived();

//         // if (timingUtil.stopwatch.elapsedMilliseconds >= (100)) {
//         // if (dReceived >= 128 && dReceived % 2 == 0) {
//         //   //   if ((timingUtil.getTotalBytesReceived() % 2) == 0) {
//         //   // TODO: implement sending of data to web worker
//         //   //     Uint8List responseOnSend = await isolateManagerInWeb.isolateManager
//         //   //         .sendMessage(timingUtil.getAllData());

//         //   // print('Response on sending to isolate: $responseOnSend');
//         //   // if (toListenStream) {
//         //   //   // _streamControllerGraph.add(timingUtil.getAllData());
//         //   // }
//         //   timingUtil.printStatistics();
//         //   // try {
//         //   //   for (int i = 0; i < timingUtil.packets.length; i++) {
//         //   //     if (i < 10 || i > (timingUtil.packets.length - 10)) {
//         //   //       print("$i : ${timingUtil.packets[i].buffer.asUint16List().first} - ${timingUtil.packets[i].buffer.asUint16List().last}");
//         //   //     }
//         //   //   }
//         //   // } catch (e) {
//         //   //   print("Reading buffer values failed.");
//         //   // }
//         //   timingUtil.reset();
//         //   }
//       }

//       //  else {
//       //  await Future.delayed(const Duration(milliseconds:500));
//       //  }
//       // }
//     } catch (e) {
//       print("Reading port failed with exception: \n$e");
//     }
//   }

//   @override
//   void dispose() {
//     isolateManagerInWeb.isolateManager.stop();
//     _port?.close();
//     super.dispose();
//   }

//   @override
//   void initState() {
//     super.initState();
//     _streamGraph = _streamControllerGraph.stream.asBroadcastStream();
//     isolateManagerInWeb.isolateManager.start();
//     // .then((value) {
//     //   _streamWebWorker = isolateManagerInWeb.isolateManager.stream;
//     //   _streamWebWorker.listen((event) {
//     //     print("received from isolate: $event");
//     //     _streamControllerGraph.add(event);
//     //   });
//     // });
//   }

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       home: Scaffold(
//           appBar: AppBar(
//             title: const Text('Flutter Serial'),
//           ),
//           body: IsolateScreenTemplate(
//             stream: _streamGraph,
//             pauseButton: () {
//               toListenStream = false;
//             },
//             resumeButton: () {
//               toListenStream = true;
//             },
//             serialPortInfo: portInfo,
//             openPort: () async {
//               await _openPort();
//             },
//             readPort: ()async {
//                await _readFromPort();
            
//             },
//             writePort: () {
//               _writeToPort();

//               //  setState(() {
//               //    isListen  = true;
//               //  });
//             },
//           )),
//     );
//   }
// }
