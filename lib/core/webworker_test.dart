import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:isolated_worker/js_isolated_worker.dart';

const List<String> _jsScripts = <String>['processing.js'];
const String _jsGetFunctionName = 'processingLoad';

class JsWebWorker {
  bool _areScriptsImported = false;

  Future<LinkedHashMap<dynamic, dynamic>> processingLoad(
      LinkedHashMap<dynamic, dynamic> arguments) async {
    if (kIsWeb) {
      if (!_areScriptsImported) {
        await JsIsolatedWorker().importScripts(_jsScripts);
        _areScriptsImported = true;
      }
      return await JsIsolatedWorker().run(
        functionName: _jsGetFunctionName,
        arguments: arguments,
      ) as LinkedHashMap<dynamic, dynamic>;
    }
    throw UnimplementedError(
      'JsWebWorker is not available for this platform.',
    );
  }
}
