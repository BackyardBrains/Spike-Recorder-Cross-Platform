import "dart:collection";
import "dart:typed_data";

import '../../core/webworker_test.dart';

class IsolatedWebWorker {
  final JsWebWorker _jsWebWorker = JsWebWorker();

  Future<dynamic> checkProcessing(Uint8List result) async {
    Stopwatch stopwatch = Stopwatch();
    stopwatch.start();

    LinkedHashMap<dynamic, dynamic> arguments =
        LinkedHashMap.from({"initialData": result});
    final LinkedHashMap<dynamic, dynamic> responseMap =
        await _jsWebWorker.processingLoad(arguments);
    final Object? error = responseMap['err'];
    if (error != null) {
      throw error;
    }
    // final dynamic totalTime = responseMap['totalTime'];
    final dynamic responseData = responseMap['response'];
    stopwatch.stop();
    // print('Response from JS: $responseData');
    // int timeTaken = stopwatch.elapsedMilliseconds;
    // print("TimeTaken for dart to dart: $timeTaken microseconds");
    // print("TimeTaken within JS: $totalTime microseconds");

    return responseData;
  }
}
