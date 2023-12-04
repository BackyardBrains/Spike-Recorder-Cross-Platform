// import 'dart:async';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:serial/serial.dart';
// import 'package:spikerbox_architecture/models/models.dart';
// import '../../../dart_isolate_function/isolate_manager/isolate_manager_in_web.dart';
// import '../../models/serial_util/serial_util_check.dart';
// import 'isolates_screen/isolate_sc_template.dart';

// class SerialPortWeb extends StatefulWidget {
//   const SerialPortWeb({Key? key}) : super(key: key);

//   @override
//   State<SerialPortWeb> createState() => _SerialPortWebState();
// }

// class _SerialPortWebState extends State<SerialPortWeb> {
//   bool toListenStream = true;
//   bool isListen = false;
//   // final IsolateManagerInWeb isolateManagerInWeb = IsolateManagerInWeb();
//   final StreamController<Uint8List> _streamControllerGraph = StreamController();
//   late Stream<Uint8List> _streamGraph;
//   SerialPort? _port;
//   SerialPortInfo? portInfo;
//   // final OpenSerialPort openSerialPort = OpenSerialPort();
//   final SerialUtil serialUtil = SerialUtil();
  

//   @override
//   void dispose() {
//     // isolateManagerInWeb.isolateManager.stop();
//     _port?.close();
//     super.dispose();
//   }

//   @override
//   void initState() {
//     super.initState();
//     _streamGraph = _streamControllerGraph.stream.asBroadcastStream();
//     // isolateManagerInWeb.isolateManager.start();
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
//         appBar: AppBar(
//           title: const Text('Flutter Serial'),
//         ),
//         body: IsolateScreenTemplate(
//           stream: _streamGraph,
//           pauseButton: () {
//             toListenStream = false;
//           },
//           resumeButton: () {
//             toListenStream = true;
//           },
//           openPort: () async {
//             //await SerialUtilWindow().openPort();
//           },
//           readPort: () async {
//           Stream<Uint8List>? getData =await serialUtil.openPortToListen("");
//          getData?.listen((event) {
//         String message = String.fromCharCodes(event);

//         print("serial received value: $event, as String: $message");
//         //         escapdeinstance.addPacket(Uint8List.fromList(message.codeUnits));
//         //         escapdeinstance.addPacket(Uint8List.fromList(message.codeUnits));
//         //         if(message.contains(":")&&message.contains(";")){
//         // print("the upcoming print is event ${event}, as String: $message");
//         //         }
//         // escapdeinstance.addPacket(Uint8List.fromList(message.codeUnits));
//         // BitwiseUtil().readBytes(Uint8List.fromList([44,255,55,69]), 10);

//         if (message.contains(":") && message.contains(";")) {}
//       });
         
//           },
//           writePort: () {
//             //  OpenSerialPort.ontapWrite("");
//             setState(() {
//               serialUtil.writeToPort(bytesMesage: UsbCommand.deviceConnection.cmdAsBytes(), address:"");
//               // SerialUtilWeb().writeToPort(bytesMesage: UsbCommand.deviceConnection.cmdAsBytes(), address:"");
//             });
//             // SerialUtil().;

//             //  setState(() {
//             //    isListen  = true;
//             //  });
//           },
//         ),
//         floatingActionButton: FloatingActionButton.extended(
//           onPressed: () async {
          
//           },
//           label: const Row(
//             children: [Text("Scan Port"), Icon(Icons.refresh)],
//           ),
//         ),
//       ),
//     );
//   }
// }
