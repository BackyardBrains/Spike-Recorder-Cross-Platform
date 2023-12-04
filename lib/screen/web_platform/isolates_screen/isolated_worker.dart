// import 'dart:async';
// import 'dart:html';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:serial/serial.dart';
// import 'package:spikerbox_architecture/models/timing_util.dart';
// import 'package:spikerbox_architecture/screen/web_platform/isolates_screen/isolate_sc_template.dart';

// import '../../../dart_isolate_function/isolate_manager/js_isolated_worker.dart';
// import '../../../models/contants.dart';
// import '../../../models/usb_protocol/commands.dart';
// import '../../graph_page_widget/sound_wave_view.dart';

// class IsolateWorkerPage extends StatefulWidget {
//   const IsolateWorkerPage({
//     Key? key,
//   }) : super(key: key);

//   @override
//   State<IsolateWorkerPage> createState() => _IsolateWorkerPageState();
// }

// class _IsolateWorkerPageState extends State<IsolateWorkerPage> {
//   IsolatedWebWorker isolatedWebWorker = IsolatedWebWorker();
//   SerialPort? _port;
//   bool toListenStream = true;
//   SerialPortInfo? portInfo;
//   final StreamController<Uint8List> _streamController = StreamController();
//   late Stream<Uint8List> _stream;

//   Future<void> _openPort() async {
//     SerialPort port = await window.navigator.serial.requestPort();
//     print(
//         "port info: productId ${port.getInfo()!.usbProductId}, vendorId: ${port.getInfo()!.usbVendorId}");
//     try {
//       await port.open(baudRate: kBaudRate, bufferSize: 1023);

//     } catch (e) {
//       print("Port opening failed.");
//     }

//     _port = port;
//     setState(() {});
//   }

//   Future<void> _writeToPort() async {
//     if (_port == null) {
//       return;
//     }

//     final writer = _port!.writable.writer;

//     try{
//       await writer.ready;
    
//     await writer.write(UsbCommand.hwVersionInquiry.cmdAsBytes());



//     await writer.ready;
//     await writer.close();
    

//     }catch (e){
//       print("the error is $e");
//     }
    
//   }

//   Future<void> _readFromPort() async {
//     if (_port == null) {
//       return;
//     }

//     try {
//       // final reader = _port!.readable.reader;
//       final reader = _port!.readable.reader;

//       // TimingUtil timingUtil = TimingUtil();

//       while (true) {
//         final ReadableStreamDefaultReadResult result = await reader.read();
//      // String message  = String.fromCharCodes(result.value);
            
//         //  if(message.contains(":")&& message.contains(";")){

//          // print("the upcoming print is event ${result.value}, as String: ${String.fromCharCodes(result.value)}");

       
//         // timingUtil.addPacket(result.value);

//         // if (timingUtil.stopwatch.elapsedMilliseconds >= (10)) {
//         //   if ((timingUtil.getTotalBytesReceived() % 2) == 0) {
//         //     var responseJS =
//         //         await isolatedWebWorker.checkProcessing(result.value);
//         //     if (responseJS is Uint8List) {
//         //       if (toListenStream) {
//         //         _streamController.add(responseJS);
//         //       }
//         //     }

//         //     timingUtil.reset();
//         //   }
//        }
//       // }
//     } catch (e) {
//       print("Reading port failed with exception: \n$e");
//     }
//   }

//   @override
//   void dispose() {
//     _port?.close();
//     super.dispose();
//   }

//   @override
//   void initState() {
//     _stream = _streamController.stream.asBroadcastStream();
//     super.initState();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       home: Scaffold(
//           appBar: AppBar(
//             title: const Text('Flutter Serial'),
//           ),
//           body: IsolateScreenTemplate(
//               stream: _stream,
//               pauseButton: () {
//                 toListenStream = false;
//               },
//               resumeButton: () {
//                 toListenStream = true;
//               },
//               serialPortInfo: portInfo,
//               openPort: () {
//                 _openPort();
//               },
//               readPort: () async {
//                 await _readFromPort();
//               },
//               writePort: ()async{
//                await _writeToPort();
//               },
//               )),
//     );
//   }
// }
