// import 'package:flutter/material.dart';
// import 'dart:async';

// import 'package:nwbfile_plugin/nwbfile_plugin.dart' as nwbfile_plugin;

// void main() {
//   runApp(const MyApp());
// }

// class MyApp extends StatefulWidget {
//   const MyApp({super.key});

//   @override
//   State<MyApp> createState() => _MyAppState();
// }

// class _MyAppState extends State<MyApp> {
//   int sumResult = 0;
//   Future<int> sumAsyncResult = Future.value(0);

//   @override
//   void initState() {
//     super.initState();
//     sumResult = nwbfile_plugin.sum(1, 2);
//     sumAsyncResult = nwbfile_plugin.sumAsync(3, 4);
//   }

//   @override
//   Widget build(BuildContext context) {
//     const textStyle = TextStyle(fontSize: 25);
//     const spacerSmall = SizedBox(height: 10);
//     return MaterialApp(
//       home: Scaffold(
//         appBar: AppBar(
//           title: const Text('Native Packages'),
//         ),
//         body: SingleChildScrollView(
//           child: Container(
//             padding: const EdgeInsets.all(10),
//             child: Column(
//               children: [
//                 const Text(
//                   'This calls a native function through FFI that is shipped as source in the package. '
//                   'The native code is built as part of the Flutter Runner build.',
//                   style: textStyle,
//                   textAlign: TextAlign.center,
//                 ),
//                 spacerSmall,
//                 Text(
//                   'sum(1, 2) = $sumResult',
//                   style: textStyle,
//                   textAlign: TextAlign.center,
//                 ),
//                 spacerSmall,
//                 FutureBuilder<int>(
//                   future: sumAsyncResult,
//                   builder: (BuildContext context, AsyncSnapshot<int> value) {
//                     final displayValue =
//                         (value.hasData) ? value.data : 'loading';
//                     return Text(
//                       'await sumAsync(3, 4) = $displayValue',
//                       style: textStyle,
//                       textAlign: TextAlign.center,
//                     );
//                   },
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }
