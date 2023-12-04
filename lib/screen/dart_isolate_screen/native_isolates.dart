import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:spikerbox_architecture/widget/custom_button.dart';

class NativeIsolateScreen extends StatefulWidget {
  const NativeIsolateScreen({super.key});

  @override
  State<NativeIsolateScreen> createState() => _NativeIsolateScreenState();
}

class _NativeIsolateScreenState extends State<NativeIsolateScreen> {
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  Isolate? isolate;

  @override
  void initState() {
    super.initState();
    _startCounterIsolate();
  }

  @override
  void dispose() {
    super.dispose();
    _receivePort!.close();
    isolate?.kill();
  }

  void _startCounterIsolate() async {
    _receivePort = ReceivePort();
    isolate = await Isolate.spawn(processingInIsolate, _receivePort!.sendPort);
    _receivePort!.listen((dynamic value) {
      if (value is SendPort) {
        _sendPort = value;
      }
    });
  }

  static void processingInIsolate(SendPort sendPort) {
    ReceivePort receivePortIsolate = ReceivePort();
    sendPort.send(receivePortIsolate.sendPort);
    receivePortIsolate.listen((message) {
      if (message is String) {
        int startTime = DateTime.now().microsecondsSinceEpoch;
        int a = 10;
        for (var i = 0; i < 100000; i++) {
          a *= a;
        }
        int timeTaken = DateTime.now().microsecondsSinceEpoch - startTime;
        print("Time taken within isolate: $timeTaken microseconds");
        sendPort.send(timeTaken);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Isolate Example'),
      ),
      body: Center(
        child: CustomButton(
          colors: Colors.blue[500],
          childWidget: const Text("Calculate again"),
          onTap: () {
            _sendPort?.send("Calculate");
          },
        ),
      ),
    );
  }
}
