import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html';
import 'package:flutter/services.dart';
import 'package:serial/serial.dart';

class SerialUtilWebCheck {
  SerialPort? _port;
  SerialPortInfo? portInfo;

  Future<void> openPortToListen(String name) async {
    _port = await window.navigator.serial.requestPort();
    try {
      await _port?.open(baudRate: 500000, bufferSize: 8192);
    } catch (e) {
      print("Port opening failed: $e");
    }
    portInfo = _port?.getInfo();
    readFromPort();
  }

  Future<void> writeToPort(
      {required Uint8List bytesMesage, required String address}) async {
    if (_port == null) {
      return;
    }

    final writer = _port!.writable.writer;

    await writer.ready;
    await writer.write(bytesMesage);
    await writer.ready;
  }
  Future<void> readFromPort() async {
    if (_port == null) {
      return;
    }
    try {
      final reader = _port!.readable.reader;

      while (true) {
//  if(isListen){

        final ReadableStreamDefaultReadResult result = await reader.read();
        String message = String.fromCharCodes(result.value);

        //  if(message.contains(":")&& message.contains(";")){

        print(
            "the upcoming print is event ${result.value}, as String: $message");

        //  }
        // timingUtil.addPacket(result.value);
        // int dReceived = timingUtil.getTotalBytesReceived();

        // if (timingUtil.stopwatch.elapsedMilliseconds >= (100)) {
        // if (dReceived >= 128 && dReceived % 2 == 0) {
        //   //   if ((timingUtil.getTotalBytesReceived() % 2) == 0) {
        //   // TODO: implement sending of data to web worker
        //   //     Uint8List responseOnSend = await isolateManagerInWeb.isolateManager
        //   //         .sendMessage(timingUtil.getAllData());

        //   // print('Response on sending to isolate: $responseOnSend');
        //   // if (toListenStream) {
        //   //   // _streamControllerGraph.add(timingUtil.getAllData());
        //   // }
        //   timingUtil.printStatistics();
        //   // try {
        //   //   for (int i = 0; i < timingUtil.packets.length; i++) {
        //   //     if (i < 10 || i > (timingUtil.packets.length - 10)) {
        //   //       print("$i : ${timingUtil.packets[i].buffer.asUint16List().first} - ${timingUtil.packets[i].buffer.asUint16List().last}");
        //   //     }
        //   //   }
        //   // } catch (e) {
        //   //   print("Reading buffer values failed.");
        //   // }
        //   timingUtil.reset();
        //   }
      }

      //  else {
      //  await Future.delayed(const Duration(milliseconds:500));
      //  }
      // }
    } catch (e) {
      print("Reading port failed with exception: \n$e");
    }
  }
}
