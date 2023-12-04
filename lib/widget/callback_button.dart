// import 'dart:async';
// import 'package:spikerbox_architecture/models/serial_util/serial_util_check.dart';
// import '../models/usb_protocol/commands.dart';
//
// class OpenSerialPort {
//   SerialUtil serialUtil = SerialUtil();
//
//   void ontapConnect(String address) {
//     serialUtil.connectToPort();
//   }
//
//   //  To listen The Port from the  web and desktop
//   Future<void> ontapListen(String? address) async {
//     serialUtil.openPortToListen(null);
//   }
//
//   //  Write the data in serial port to any device
//   Future<void> ontapWrite(String address) async {
//     serialUtil.writeToPort(
//         address: address,
//         bytesMesage: UsbCommand.deviceConnection.cmdAsBytes());
//   }
// }
