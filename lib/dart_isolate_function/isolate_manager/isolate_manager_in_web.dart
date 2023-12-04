// import 'dart:async';
// import 'dart:typed_data';

// import 'package:isolate_manager/isolate_manager.dart';

// class IsolateManagerInWeb {
//   final IsolateManager<Uint8List> isolateManager =
//       IsolateManager.createOwnIsolate(
//     concurrent: 1,
//     isolateFunction,
//     isDebug: false,
//   );

//   /// Create your own function here. This function will be called when your isolate started.
//   @pragma('vm:entry-point')
//   static void isolateFunction(dynamic params) {
//     // Initial the controller for child isolate
//     final IsolateManagerController<Uint8List> controller =
//         IsolateManagerController<Uint8List>(params, onDispose: () {
//       print('Dispose isolateFunction');
//     });

//     // Get your initialParams.
//     // Notice that this `initialParams` different from the `params` above.
//     final initialParams = controller.initialParams;

//     // Do your one-time stuff here, this area of code will be called only one-time when you `start`
//     // this instance of `IsolateManager`

//     // Listen to the message receiving from main isolate, this area of code will be called each time
//     // you use `compute` or `sendMessage`.
//     controller.onIsolateMessage.listen((message) {
//       if (message is Uint8List) {
//         // Create a completer
//         Completer completer = Completer();

//         // Handle the result an exceptions
//         completer.future.then(
//           (value) => controller.sendResult(value as Uint8List),
//           onError: (err, stack) =>
//               controller.sendResult(Uint8List.fromList(<int>[])
//                   // IsolateException(err, stack) as Uint8List
//                   ),
//         );

//         // Use try-catch to send the exception to the main app
//         try {
//           // print("Msg length : ${(message).length}");
//           // print("My msg received in isolate: $message");
//           // completer.complete(Uint8List.fromList(message.toList().map((e) => e~/2).toList()));
//           completer.complete(message);
//         } catch (err, stack) {
//           // Send the exception to your main app
//           controller.sendResult(Uint8List.fromList(<int>[]));
//         }
//       }
//     });
//   }
// }
