import 'package:flutter/services.dart';
// import 'package:flutter_js/flutter_js.dart';

// class WabImplementation {

//  late JavascriptRuntime jsRunTime = getJavascriptRuntime();

  
//   Future<int> addFromJs(JavascriptRuntime javascriptRuntime, int firstNumber,
//       int secondNumber) async {
//     String blocjs = await rootBundle.loadString("lib");
//     final jsResult =
//         jsRunTime.evaluate("""${blocjs}add($firstNumber,$secondNumber)""");
//     final jsStringResult = jsResult.stringResult;
//     return int.parse(jsStringResult);
//   }
// }