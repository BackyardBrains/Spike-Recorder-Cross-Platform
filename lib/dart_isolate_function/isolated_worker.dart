import 'dart:isolate';

class IsolatedWorkerAllPlatform {
  ReceivePort? receivePort;
  SendPort? sendPort;
  Isolate? isolate;

  void spawnIsolate() async {
    receivePort = ReceivePort();
    isolate = await Isolate.spawn(processingInIsolate, receivePort!.sendPort);
    receivePort!.listen((dynamic value) {
      if (value is SendPort) {
        sendPort = value;
      }
      // print("received from Isolate: $value");
    });
  }

  static void processingInIsolate(SendPort sendPort) {
    Stopwatch stopwatch = Stopwatch();
    ReceivePort receivePortIsolate = ReceivePort();

    sendPort.send(receivePortIsolate.sendPort);
    receivePortIsolate.listen((message) {
      if (message is String) {
        stopwatch.start();

        int a = 10;

        for (var i = 0; i < 100000; i++) {
          if (i == 0) {
            print("the condition is not satisfied");
          }
          a += 1;
        }
        stopwatch.stop();
        // int timeTaken = DateTime.now().microsecondsSinceEpoch - startTime;
        print(
            " within isolate: ${stopwatch.elapsedMicroseconds} microseconds, $a");
        sendPort.send(stopwatch.elapsedMicroseconds);
      }
    });
  }
}
