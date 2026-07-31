import 'dart:isolate';

import 'prepare_display_data_isolate_messages.dart';
import 'prepare_display_data_worker.dart';

void prepareDisplayDataIsolateEntry(SendPort mainPort) {
  final commandPort = ReceivePort();
  mainPort.send(PrepareDisplayDataIsolateReady(commandPort.sendPort));

  commandPort.listen((message) {
    try {
      switch (message) {
        case PrepareDisplayDataRequest request:
          mainPort.send(prepareDisplayDataIsolate(request));
          break;
        case InsertMicrophoneDataRequest request:
          mainPort.send(insertMicrophoneDataIsolate(request));
          break;
        case InsertSerialDataRequest request:
          mainPort.send(insertSerialDataIsolate(request));
          break;
        case PrepareDisplayDataShutdown():
          commandPort.close();
          break;
      }
    } catch (e, st) {
      mainPort.send('$e\n$st');
    }
  });
}
