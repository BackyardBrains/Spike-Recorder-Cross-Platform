import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'serial_util_check.dart';
import 'dart:convert';


class SerialUtilWindow implements SerialUtil {
  @override
  bool isOpeningFile = false;
  SerialPort? port;
  int _baudRate = 0;

  @override
  List<String> availablePorts = [];

  @override
  Stream<Uint8List>? dataStream;

  @override
  Future<List<String>> startPortCheck(int baudRate) async {
    // Timer.periodic(Duration(seconds: 5), (timer) {
    availablePorts = SerialPort.availablePorts;
    // });
    return availablePorts;
  }

  // get the list of current ports
  @override
  Future<void> getAvailablePorts(int baudRate, Function callback) async {
    availablePorts = await startPortCheck(9600); // Adjust baudRate as needed

    // Wait for 5 seconds before the next check
  }

  @override
  void writeToPort({required Uint8List bytesMessage, String? address}) {
    if (port?.name == address) {
      try {
        print("writing to port: ${utf8.decode(bytesMessage)}");
        final intsize = port?.write(bytesMessage);
        print("command is sent. Length: $intsize, cmd: ${intsize}");
      } catch (err, _) {
        port!.close();
      }
    }
  }

  @override
  void setConfig() {
    SerialPortConfig config = SerialPortConfig();
    config.baudRate = _baudRate;
    config.bits = 8;
    config.stopBits = 1;
    port!.config = config;
  }

  bool _openPort() {
    bool isOpen = false;
    if (!port!.isOpen) {
      isOpen = port!.openReadWrite();
    }
    setConfig();
    return isOpen;
  }

  @override
  void closePort() {
    reader.close();
    port!.close();
  }

  @override
  Future<int> connectToPort() {
    return Future.value(0);
  }

  late SerialPortReader reader;
  StreamSubscription? serialBufferSubscription;
  StreamController<Uint8List> _serialBufferController = StreamController();
  Uint8List serialBuffer = Uint8List(1200);
  List<int> serialBufferList = [];
  int headIdx = 0;
  int bufferLimit = 1024;
  @override
  Future<Stream<Uint8List>?> openPortToListen(
      String? portName, int baudRate) async {
    if (serialBufferSubscription != null) {
      serialBufferSubscription?.cancel();
    }

    _baudRate = baudRate;
    // checkEscapeSequence();
    if (portName == null) return null;
    port = SerialPort(portName);

    if (port?.name == portName) {
      if (!port!.isOpen) !_openPort();
      reader = SerialPortReader(port!);
      /*
      serialBufferSubscription = reader.stream.listen((data){
        for (int i = 0; i < data.length; i++) {
          // serialBuffer[headIdx] = data[i];
          serialBufferList.add(data[i]);
          headIdx++;
        }
        if (headIdx > bufferLimit) {
          headIdx = 0;
          // print("serialBufferList: $serialBufferList");
          // serialBufferList.clear();
          // final resBuffer = serialBuffer.sublist(0,bufferLimit);
          // print("resBuffer ${resBuffer.length}");
          // print(resBuffer);
          // _serialBufferController.add(resBuffer);

          // // print("SerialBuffer length: ${serialBuffer.length} $headIdx");
          // final residueBuffer = Uint8List.fromList(serialBuffer.sublist(bufferLimit , headIdx));
          // headIdx = 0;
          // final residueBufferLen = residueBuffer.length;
          // if (residueBufferLen > 0) {
          //   for (int i = 0; i < residueBufferLen; i++) {
          //     serialBuffer[i] = data[i];
          //     headIdx++;
          //   }
          //   serialBuffer.fillRange(residueBufferLen, 1200, 0);
          // }
        }
      });
      return _serialBufferController.stream.asBroadcastStream();
      */
      return reader.stream;
    }
    return null;
  }

  @override
  void streamListen({required Stream<Uint8List>? getData}) {
    try {
      getData?.listen((event) {
        String message = String.fromCharCodes(event);

        // print("serial received value: $event, as String: $message");
        //         escapdeinstance.addPacket(Uint8List.fromList(message.codeUnits));
        //         escapdeinstance.addPacket(Uint8List.fromList(message.codeUnits));
        //         if(message.contains(":")&&message.contains(";")){
        // print("the upcoming print is event ${event}, as String: $message");
        //         }
        // escapdeinstance.addPacket(Uint8List.fromList(message.codeUnits));
        // BitwiseUtil().readBytes(Uint8List.fromList([44,255,55,69]), 10);
        if (message.contains(":") && message.contains(";")) {}
      });
    } catch (e) {}
  }

  @override
  Future<List<String>> getAvailablePortsWeb(
      int baudRate, Function audioCallback) {
    return Future.value([]);
  }

  @override
  Stream<String?> deviceStatusStreamListener() {
    return Stream.empty();
  }
}
