// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:native_add/model/model.dart';
// import 'package:provider/provider.dart';
// import 'package:spikerbox_architecture/models/models.dart';
// import 'package:spikerbox_architecture/provider/provider_export.dart';

// import '../constant/const_export.dart';
// import '../widget/widget_export.dart';
// import 'graph_template.dart';

// class SettingPage extends StatefulWidget {
//   const SettingPage({super.key, required this.settingPage});
//   final Widget settingPage;

//   @override
//   State<SettingPage> createState() => _SettingPageState();
// }

// class _SettingPageState extends State<SettingPage> {
//   double _sliderValue = 25;
//   double startValue = 0;
//   double endValue = 22000;
//   LocalPlugin localPlugin = LocalPlugin();
//   final SerialUtil _serialUtil = SerialUtil();

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: Container(
//         color: const Color.fromARGB(228, 49, 49, 52),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.center,
//           children: [
//             Row(children: [
//               SpikerBoxButton(
//                   onTapButton: () {
//                     context.read<SoftwareConfigProvider>().settingStatus(false);
//                   },
//                   iconData: Icons.settings),
//               const SizedBox(
//                 width: 10,
//               ),
//               Text(
//                 "Config",
//                 style: SoftwareTextStyle().kWtMediumTextStyle,
//               )
//             ]),
//             SizedBox(
//               width: 500,
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   CustomSliderBarButton(
//                     startValue: startValue,
//                     endValue: endValue,
//                     min: 0,
//                     max: 22000,
//                     sliderValue: _sliderValue,
//                     onSlider: (double sliderValue) {
//                       _sliderValue = sliderValue;
//                     },
//                   )
//                 ],
//               ),
//             ),
//             const SizedBox(
//               height: 10,
//             ),
//             Row(
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 Text(
//                   "Alternate frequency (Notch filter) : ",
//                   style: SoftwareTextStyle().kWtMediumTextStyle,
//                 ),
//                 Row(
//                   children: [
//                     Text(
//                       "50 Hz",
//                       style: SoftwareTextStyle().kWtMediumTextStyle,
//                     ),
//                     WhiteColorCheckBox(
//                       valueStatus: false,
//                       onChanged: (value) {},
//                     ),
//                   ],
//                 ),
//                 const SizedBox(
//                   width: 10,
//                 ),
//                 Row(
//                   children: [
//                     Text(
//                       "60 Hz",
//                       style: SoftwareTextStyle().kWtMediumTextStyle,
//                     ),
//                     WhiteColorCheckBox(
//                       valueStatus: false,
//                       onChanged: (value) {},
//                     ),
//                   ],
//                 )
//               ],
//             ),
//             const SizedBox(
//               height: 10,
//             ),
//             SettingPage(
//               settingPage: SizedBox(
//                 height: 250,
//                 width: 400,
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.center,
//                   children: [
//                     Consumer<PortScanProvider>(
//                         builder: (context, portList, snapshot) {
//                       return _PortsArea(
//                         deviceName: _deviceName,
//                         availablePorts: portList.availablePorts,
//                         onReceive: (String add) async {
//                           int baudRate =
//                               context.read<ConstantProvider>().getBaudRate();
//                           Stream<Uint8List>? getData =
//                               await _serialUtil.openPortToListen(add, baudRate);

//                           if (!mounted) return;
//                           bool dummyDataStatus =
//                               context.read<DataStatusProvider>().isSampleDataOn;
//                           bool isAudioListen = context
//                               .read<DataStatusProvider>()
//                               .isMicrophoneData;

//                           getData?.listen((event) {
//                             if (!dummyDataStatus && !isAudioListen) {
//                               _preEscapeSequenceBuffer.addBytes(event);
//                               if (isDeviceConnect) {
//                                 _serialUtil.writeToPort(
//                                     bytesMessage:
//                                         UsbCommand.hwTypeInquiry.cmdAsBytes(),
//                                     address: add);

//                                 isDeviceConnect = false;
//                               }
//                               if (_isDataIdentified) {
//                                 // Debugging.printing('us: ${stopwatch.elapsedMicroseconds}, length : ${event.length}');
//                                 // stopwatch.reset();
//                               } else {
//                                 Uint8List? firstFrameData =
//                                     _frameDetect.addData(event);

//                                 if (firstFrameData != null) {
//                                   _preEscapeSequenceBuffer
//                                       .addBytes(firstFrameData);
//                                   _isDataIdentified = true;
//                                 }
//                               }
//                             }
//                           });
//                           portName = add;
//                         },
//                         onWrite: (String add) async {
//                           MessageValueSet? selectedCommand =
//                               await showCommandPopUp(add);
//                           if (selectedCommand != null) {
//                             _serialUtil.writeToPort(
//                                 bytesMessage: selectedCommand.cmdAsBytes(),
//                                 address: add);
//                           }
//                         },
//                       );
//                     }),
//                     Expanded(
//                       child: SingleChildScrollView(
//                         child: Column(
//                           children: [
//                             FilterProcessWidget(
//                                 isMicrophoneEnable: (bool isMicrophoneEnable) {
//                               // _toEnableMicrophone =
//                               //     isMicrophoneEnable;
//                               context
//                                   .read<DataStatusProvider>()
//                                   .setMicrophoneDataStatus(isMicrophoneEnable);
//                             }, onHighPassFilterSetup:
//                                     (FilterSetup filterSetup) {
//                               localPlugin.initHighPassFilters(filterSetup);
//                             }, onLowPassFilterSetup: (FilterSetup filterSetup) {
//                               localPlugin.initLowPassFilters(filterSetup);
//                             }, onSampleChange: (bool isSampleDataOn) {
//                               context
//                                   .read<DataStatusProvider>()
//                                   .setSampleDataStatus(isSampleDataOn);
//                               // _toGenerateDummyData =
//                               //     isSampleDataOn;
//                             }),
//                             DropdownButtonFormField<int>(
//                               dropdownColor:
//                                   SoftwareColors.kDropDownBackGroundColor,
//                               style: SoftwareTextStyle().kWtMediumTextStyle,
//                               items: _dataBit
//                                   .map(
//                                     (e) => DropdownMenuItem(
//                                       value: e,
//                                       child: Text(
//                                         e.toString(),
//                                       ),
//                                     ),
//                                   )
//                                   .toList(),
//                               onChanged: (int? bitDataSelect) {
//                                 context
//                                     .read<ConstantProvider>()
//                                     .setBitData(bitDataSelect!);
//                               },
//                               value:
//                                   context.read<ConstantProvider>().getBitData(),
//                             ),
//                             DropdownButtonFormField(
//                               dropdownColor:
//                                   SoftwareColors.kDropDownBackGroundColor,
//                               style: SoftwareTextStyle().kWtMediumTextStyle,
//                               items: _baudRate
//                                   .map(
//                                     (e) => DropdownMenuItem(
//                                       value: e,
//                                       child: Text(
//                                         e.toString(),
//                                       ),
//                                     ),
//                                   )
//                                   .toList(),
//                               onChanged: (baudRateSelect) {
//                                 context
//                                     .read<ConstantProvider>()
//                                     .setBaudRate(baudRateSelect!);
//                               },
//                               value: context
//                                   .read<ConstantProvider>()
//                                   .getBaudRate(),
//                             ),
//                             DropdownButtonFormField(
//                               dropdownColor:
//                                   SoftwareColors.kDropDownBackGroundColor,
//                               style: SoftwareTextStyle().kWtMediumTextStyle,
//                               items: _channelCount
//                                   .map(
//                                     (e) => DropdownMenuItem(
//                                       value: e,
//                                       child: Text(
//                                         e.toString(),
//                                       ),
//                                     ),
//                                   )
//                                   .toList(),
//                               onChanged: (int? channelCountSelect) {
//                                 context
//                                     .read<ConstantProvider>()
//                                     .setChannelCount(channelCountSelect!);
//                               },
//                               value: context
//                                   .read<ConstantProvider>()
//                                   .getChannelCount(),
//                             ),
//                           ],
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _PortsArea extends StatelessWidget {
//   const _PortsArea(
//       {required this.deviceName,
//       required this.availablePorts,
//       required this.onReceive,
//       required this.onWrite});

//   final ValueNotifier<String?> deviceName;
//   final List<String> availablePorts;
//   final Function(String) onReceive;
//   final Function(String) onWrite;

//   @override
//   Widget build(BuildContext context) {
//     return SingleChildScrollView(
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.start,
//         children: [
//           for (final address in availablePorts)
//             Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 Expanded(
//                   child: Text(address,
//                       style: SoftwareTextStyle().kWtMediumTextStyle),
//                 ),
//                 Flexible(
//                   child: SizedBox(
//                     child: CustomButton(
//                       childWidget: Text(
//                         "Connect",
//                         style: SoftwareTextStyle().kBBkMediumTextStyle,
//                       ),
//                       colors: SoftwareColors.kButtonBackGroundColor,
//                       onTap: () => onReceive(address),
//                     ),
//                   ),
//                 ),
//                 Flexible(
//                   child: SizedBox(
//                     child: CustomButton(
//                       colors: SoftwareColors.kButtonBackGroundColor,
//                       childWidget: Text(
//                         "Write",
//                         style: SoftwareTextStyle().kBBkMediumTextStyle,
//                       ),
//                       onTap: () => onWrite(address),
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           ValueListenableBuilder<String?>(
//             valueListenable: deviceName,
//             builder: (context, snapshot, _) {
//               return snapshot != null
//                   ? Card(
//                       child: Padding(
//                         padding: const EdgeInsets.all(8.0),
//                         child: Text(snapshot),
//                       ),
//                     )
//                   : const SizedBox.shrink();
//             },
//           ),
//         ],
//       ),
//     );
//   }
// }

import 'package:flutter/material.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key, required this.settingPage});
  final Widget settingPage;

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  @override
  Widget build(BuildContext context) {
    return widget.settingPage;
  }
}
