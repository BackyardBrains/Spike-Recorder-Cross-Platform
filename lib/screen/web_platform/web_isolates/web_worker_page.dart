import 'dart:collection';

import 'package:flutter/material.dart';

import '../../../core/webworker_test.dart';

class WebWorkerPage extends StatefulWidget {
  const WebWorkerPage({Key? key}) : super(key: key);

  @override
  State<WebWorkerPage> createState() => _WebWorkerPageState();
}

class _WebWorkerPageState extends State<WebWorkerPage> {
  final JsWebWorker _jsWebWorker = JsWebWorker();

  @override
  void initState() {
    super.initState();
    _checkProcessing();

    // await isolateManager.start();
  }

  Future<void> _checkProcessing() async {
    int startTime = DateTime.now().microsecondsSinceEpoch;

    LinkedHashMap<dynamic, dynamic> arguments =
        LinkedHashMap.from({"initialData": 55});
    final LinkedHashMap<dynamic, dynamic> responseMap =
        await _jsWebWorker.processingLoad(arguments);
    final Object? error = responseMap['err'];
    if (error != null) {
      throw error;
    }
    final dynamic totalTime = responseMap['totalTime'];
    int timeTaken = DateTime.now().microsecondsSinceEpoch - startTime;
    print("TimeTaken for dart to dart: $timeTaken microseconds");
    print("TimeTaken within JS: $totalTime microseconds");
    return;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IsolatedWorker fetch example'),
      ),
      body: Column(
        children: [
          ElevatedButton(
            child: const Text("processing"),
            onPressed: () {
              _checkProcessing();
            },
          ),
        ],
      ),
    );
  }
}
