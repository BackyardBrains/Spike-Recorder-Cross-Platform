import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:native_add/model/model.dart';
import 'package:provider/provider.dart';
import 'package:spikerbox_architecture/constant/const_export.dart';
import 'package:spikerbox_architecture/models/global_buffer.dart';
import 'package:spikerbox_architecture/models/models.dart';
import 'package:spikerbox_architecture/provider/provider_export.dart';
import 'package:spikerbox_architecture/screen/screen_export.dart';

import '../widget/widget_export.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({
    super.key,
  });

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  final List<int> _dataBit = [14, 10];
  final List<int> _baudRate = [222222, 230400, 500000];
  final List<int> _channelCount = [1, 2];
  bool isDeviceConnect = true;

  @override
  Widget build(BuildContext context) {
    ConstantProvider constantProvider = Provider.of<ConstantProvider>(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          children: [
            SpikerBoxButton(
              onTapButton: () {
                context.read<SoftwareConfigProvider>().settingStatus(false);
              },
              iconData: Icons.settings,
            ),
          ],
        ),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 500,
            ),
            child: Column(
              children: [
                CustomSliderBarButton(
                  isMicrophoneEnable: (bool isMicrophoneEnable) {
                    context
                        .read<DataStatusProvider>()
                        .setMicrophoneDataStatus(isMicrophoneEnable);
                  },
                  onHighPassFilterSetup: (FilterSetup filterSetup) {
                    localPlugin.initHighPassFilters(filterSetup);
                  },
                  onLowPassFilterSetup: (FilterSetup filterSetup) {
                    localPlugin.initLowPassFilters(filterSetup);
                  },
                  onSampleChange: (bool isSampleDataOn) {
                    context
                        .read<DataStatusProvider>()
                        .setSampleDataStatus(isSampleDataOn);
                    // _toGenerateDummyData =
                    //     isSampleDataOn;
                  },
                ),
                const SizedBox(
                  height: 10,
                ),
                NotchPassFilterWidget(
                  onTapNotchFrequency: (notchFilterSettings) {
                    context
                        .read<DataStatusProvider>()
                        .setNotchPassFilterSetting(notchFilterSettings);
                    localPlugin.initNotchFilters(notchFilterSettings);
                  },
                ),
                const SizedBox(
                  height: 10,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 1,
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              FilterProcessWidget(
                                  onTapDebugging: (bool debuggingStatus) {
                                // isDebugging = debuggingStatus;
                              }, isMicrophoneEnable: (bool isMicrophoneEnable) {
                                context
                                    .read<DataStatusProvider>()
                                    .setMicrophoneDataStatus(
                                        isMicrophoneEnable);
                              }, onSampleChange: (bool isSampleDataOn) {
                                context
                                    .read<DataStatusProvider>()
                                    .setSampleDataStatus(isSampleDataOn);
                                // _toGenerateDummyData =
                                //     isSampleDataOn;
                              }),
                              DropdownButtonFormField<int>(
                                dropdownColor:
                                    SoftwareColors.kDropDownBackGroundColor,
                                style: SoftwareTextStyle().kWtMediumTextStyle,
                                items: _dataBit
                                    .map(
                                      (e) => DropdownMenuItem(
                                        value: e,
                                        child: Text(
                                          e.toString(),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (int? bitDataSelect) {
                                  constantProvider.setBitData(bitDataSelect!);
                                },
                                value: constantProvider.getBitData(),
                              ),
                              DropdownButtonFormField(
                                dropdownColor:
                                    SoftwareColors.kDropDownBackGroundColor,
                                style: SoftwareTextStyle().kWtMediumTextStyle,
                                items: _baudRate
                                    .map(
                                      (e) => DropdownMenuItem(
                                        value: e,
                                        child: Text(
                                          e.toString(),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (baudRateSelect) {
                                  constantProvider.setBaudRate(baudRateSelect!);
                                },
                                value: constantProvider.getBaudRate(),
                              ),
                              DropdownButtonFormField(
                                dropdownColor:
                                    SoftwareColors.kDropDownBackGroundColor,
                                style: SoftwareTextStyle().kWtMediumTextStyle,
                                items: _channelCount
                                    .map(
                                      (e) => DropdownMenuItem(
                                        value: e,
                                        child: Text(
                                          e.toString(),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (int? channelCountSelect) {
                                  constantProvider
                                      .setChannelCount(channelCountSelect!);
                                },
                                value: constantProvider.getChannelCount(),
                              ),
                              const DebugTheDataDetail()
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                          flex: 1,
                          child: kIsWeb
                              ? Consumer<PortScanProvider>(
                                  builder: (context, portList, snapshot) {
                                  // print(
                                  //     "the length of port is ${portList.availablePorts.length}");
                                  if (portList.availablePorts.isEmpty) {
                                    return const SizedBox.shrink();
                                  } else {
                                    return _PortsArea(
                                      deviceName: portList.availablePorts.first,
                                      availablePorts: portList.availablePorts,
                                      onReceive: (String add) async {
                                        int baudRate = context
                                            .read<ConstantProvider>()
                                            .getBaudRate();

                                        serialUtil.openPortToListen(
                                            add, baudRate);
                                        context
                                            .read<DataStatusProvider>()
                                            .setMicrophoneDataStatus(false);

                                        if (!mounted) return;
                                        bool dummyDataStatus = context
                                            .read<DataStatusProvider>()
                                            .isSampleDataOn;
                                        bool isAudioListen = context
                                            .read<DataStatusProvider>()
                                            .isMicrophoneData;

                                        try {
                                          serialUtil.dataStream
                                              ?.listen((event) {
                                            if (!dummyDataStatus &&
                                                !isAudioListen) {
                                              preEscapeSequenceBuffer
                                                  .addBytes(event);
                                              if (isDeviceConnect) {
                                                serialUtil.writeToPort(
                                                    bytesMessage: UsbCommand
                                                        .hwTypeInquiry
                                                        .cmdAsBytes(),
                                                    address: add);

                                                isDeviceConnect = false;
                                              }
                                              if (isDataIdentified) {
                                                // Debugging.printing('us: ${stopwatch.elapsedMicroseconds}, length : ${event.length}');
                                                // stopwatch.reset();
                                              } else {
                                                Uint8List? firstFrameData =
                                                    frameDetect.addData(event);

                                                if (firstFrameData != null) {
                                                  preEscapeSequenceBuffer
                                                      .addBytes(firstFrameData);
                                                  isDataIdentified = true;
                                                }
                                              }
                                            }
                                          });
                                          // portName = add;
                                        } catch (e) {
                                          print(
                                              "the error is $e from serial port");
                                        }
                                      },
                                      onWrite: (String add) async {
                                        MessageValueSet? selectedCommand =
                                            await showCommandPopUp(add);
                                        if (selectedCommand != null) {
                                          serialUtil.writeToPort(
                                              bytesMessage:
                                                  selectedCommand.cmdAsBytes(),
                                              address: add);
                                        }
                                      },
                                    );
                                  }
                                })
                              : Consumer<PortScanProvider>(
                                  builder: (context, portList, snapshot) {
                                  if (portList.deviceList.isEmpty) {
                                    return SizedBox.shrink();
                                  } else {
                                    return _PortsArea(
                                      deviceName: portList.deviceList.last,
                                      availablePorts: portList.availablePorts,
                                      onReceive: (String add) async {
                                        int baudRate = context
                                            .read<ConstantProvider>()
                                            .getBaudRate();

                                        serialUtil.openPortToListen(
                                            add, baudRate);
                                        context
                                            .read<DataStatusProvider>()
                                            .setMicrophoneDataStatus(false);

                                        if (!mounted) return;
                                        bool dummyDataStatus = context
                                            .read<DataStatusProvider>()
                                            .isSampleDataOn;
                                        bool isAudioListen = context
                                            .read<DataStatusProvider>()
                                            .isMicrophoneData;
                                        try {
                                          serialUtil.dataStream
                                              ?.listen((event) {
                                            if (!dummyDataStatus &&
                                                !isAudioListen) {
                                              preEscapeSequenceBuffer
                                                  .addBytes(event);
                                              if (isDeviceConnect) {
                                                serialUtil.writeToPort(
                                                    bytesMessage: UsbCommand
                                                        .hwTypeInquiry
                                                        .cmdAsBytes(),
                                                    address: add);

                                                isDeviceConnect = false;
                                              }
                                              if (isDataIdentified) {
                                                // Debugging.printing('us: ${stopwatch.elapsedMicroseconds}, length : ${event.length}');
                                                // stopwatch.reset();
                                              } else {
                                                Uint8List? firstFrameData =
                                                    frameDetect.addData(event);

                                                if (firstFrameData != null) {
                                                  preEscapeSequenceBuffer
                                                      .addBytes(firstFrameData);
                                                  isDataIdentified = true;
                                                }
                                              }
                                            }
                                          });
                                          // portName = add;
                                        } catch (e) {
                                          print(
                                              "the error is $e from serial port");
                                        }
                                      },
                                      onWrite: (String add) async {
                                        MessageValueSet? selectedCommand =
                                            await showCommandPopUp(add);
                                        if (selectedCommand != null) {
                                          serialUtil.writeToPort(
                                              bytesMessage:
                                                  selectedCommand.cmdAsBytes(),
                                              address: add);
                                        }
                                      },
                                    );
                                  }
                                })),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<MessageValueSet?> showCommandPopUp(String add) async {
    List<DropdownMenuItem<MessageValueSet>> items = UsbCommand.commandList
        .map(
          (e) => DropdownMenuItem(
            value: e,
            child: Text(e.toString()),
          ),
        )
        .toList();

    MessageValueSet? selection;

    var result = await showDialog(
      barrierDismissible: false,
      context: context,
      builder: (BuildContext build) {
        MessageValueSet selectedValue = items.first.value!; // Default value
        return AlertDialog(
            icon: DropdownButtonFormField(
              items: items,
              onChanged: (MessageValueSet? dropDownChanges) {
                setState(() {
                  selectedValue = dropDownChanges
                      as MessageValueSet; // Update selected value
                });
              },
              value: selectedValue, // Use the selected value
            ),
            actions: [
              CustomButton(
                colors: Colors.blue[400],
                childWidget: const Text("Back"),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              CustomButton(
                colors: Colors.blue[400],
                childWidget: const Text("Write"),
                onTap: () {
                  Navigator.pop(context, selectedValue);
                },
              )
            ]);
      },
    );

    if (result != null) {
      if (result is MessageValueSet) {
        return result;
      }
    }
    return selection;
  }
}

class FilterProcessWidget extends StatefulWidget {
  const FilterProcessWidget(
      {super.key,
      required this.onSampleChange,
      required this.isMicrophoneEnable,
      required this.onTapDebugging});

  final Function(bool) isMicrophoneEnable;
  final Function(bool) onSampleChange;
  final Function(bool) onTapDebugging;

  @override
  State<FilterProcessWidget> createState() => _FilterProcessWidgetState();
}

class _FilterProcessWidgetState extends State<FilterProcessWidget> {
  @override
  Widget build(BuildContext context) {
    return Consumer<DataStatusProvider>(
        builder: (context, dataStatus, snapshot) {
      return Column(
        children: [
          Row(
            children: [
              WhiteColorCheckBox(
                valueStatus: dataStatus.isSampleDataOn,
                onChanged: (value) {
                  if (dataStatus.isMicrophoneData) {
                    listenPort?.cancel();

                    dataStatus.setMicrophoneDataStatus(false);
                    dataStatus.setSampleDataStatus(true);
                    Provider.of<SampleRateProvider>(context, listen: false)
                        .setSampleRate(dummySamplingRate);
                  } else if (!dataStatus.isMicrophoneData) {}
                  dataStatus.setSampleDataStatus(value!);

                  // setState(() {
                  //   _isSampleDataOn = value ?? false;
                  //   if (_isSampleDataOn && _isMicrophoneEnable) {
                  //     _isMicrophoneEnable = false;
                  //     widget.isMicrophoneEnable(_isMicrophoneEnable);
                  //   }
                  // });
                  // Provider.of<SampleRateProvider>(context, listen: false)
                  //     .setSampleRate(dummySamplingRate);
                  // // Provider.of<GraphDataProvider>(context, listen: false)
                  // //     .setBufferLength(dummySamplingRate);
                },
              ),
              Text(
                "Sample Data ",
                style: SoftwareTextStyle().kWtMediumTextStyle,
              ),
              WhiteColorCheckBox(
                valueStatus: dataStatus.isDebugging,
                onChanged: (value) {
                  widget.onTapDebugging(value ?? false);
                  dataStatus.setDebuggingDataStatus(value ?? false);
                },
              ),
              Flexible(
                child: Text(
                  "Debugger Open",
                  style: SoftwareTextStyle().kWtMediumTextStyle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              WhiteColorCheckBox(
                valueStatus: dataStatus.isMicrophoneData,
                onChanged: (value) {
                  if (dataStatus.isSampleDataOn) {
                    listenPort?.cancel();
                    dataStatus.setMicrophoneDataStatus(true);
                    dataStatus.setSampleDataStatus(false);
                    Provider.of<SampleRateProvider>(context, listen: false)
                        .setSampleRate(dummySamplingRate);
                  } else {
                    dataStatus.setMicrophoneDataStatus(value!);
                  }

                  // setState(() {
                  //   _isMicrophoneEnable = value ?? false;
                  //   if (_isMicrophoneEnable && _isSampleDataOn) {
                  //     _isSampleDataOn = false;
                  //     widget.onSampleChange(_isSampleDataOn);
                  //   }
                  // });
                  // widget.isMicrophoneEnable(_isMicrophoneEnable);
                },
              ),
              Text(
                "Microphone On",
                style: SoftwareTextStyle().kWtMediumTextStyle,
              )
            ],
          ),
        ],
      );
    });
  }
}

class NotchPassFilterWidget extends StatefulWidget {
  const NotchPassFilterWidget({
    super.key,
    required this.onTapNotchFrequency,
  });

  final Function(FilterSetup) onTapNotchFrequency;

  @override
  State<NotchPassFilterWidget> createState() => _NotchPassFilterWidgetState();
}

class _NotchPassFilterWidgetState extends State<NotchPassFilterWidget> {
  bool isNotch50 = false;
  bool isNotch60 = false;
  final double _sampleRate = 0;
  late FilterSetup _notchPassFilterSettings;
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<SampleRateProvider, DataStatusProvider>(
        builder: (context, sampleRate, dataStatus, snapshot) {
      isNotch60 = dataStatus.is60Hertz;
      isNotch50 = dataStatus.is50Hertz;
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "Alternate frequency (Notch filter) : ",
            style: SoftwareTextStyle().kWtMediumTextStyle,
          ),
          Row(
            children: [
              Text(
                "50 Hz",
                style: SoftwareTextStyle().kWtMediumTextStyle,
              ),
              WhiteColorCheckBox(
                valueStatus: dataStatus.is50Hertz,
                onChanged: (value) {
                  _notchPassFilterSettings = dataStatus.notchPassFilterSettings;
                  if (isNotch60) {
                    dataStatus.set60HertzStatus(false);
                  }
                  isNotch50 = value!;

                  dataStatus.set50HertzStatus(value);

                  _notchPassFilterSettings = _notchPassFilterSettings.copyWith(
                      filterType: FilterType.notchFilter,
                      isFilterOn: value,
                      filterConfiguration: FilterConfiguration(
                          cutOffFrequency: 50,
                          sampleRate: sampleRate.sampleRate));
                  widget.onTapNotchFrequency(_notchPassFilterSettings);
                },
              ),
            ],
          ),
          const SizedBox(
            width: 10,
          ),
          Row(
            children: [
              Text(
                "60 Hz",
                style: SoftwareTextStyle().kWtMediumTextStyle,
              ),
              WhiteColorCheckBox(
                valueStatus: dataStatus.is60Hertz,
                onChanged: (value) {
                  if (isNotch50) {
                    dataStatus.set50HertzStatus(false);
                    isNotch60 = value!;
                  } else {
                    isNotch60 = value!;
                  }
                  dataStatus.set60HertzStatus(value);
                  _notchPassFilterSettings = _notchPassFilterSettings.copyWith(
                      filterType: FilterType.notchFilter,
                      isFilterOn: value,
                      filterConfiguration: FilterConfiguration(
                          cutOffFrequency: 60,
                          sampleRate: sampleRate.sampleRate));
                  widget.onTapNotchFrequency(_notchPassFilterSettings);
                },
              ),
            ],
          )
        ],
      );
    });
  }
}

class _PortsArea extends StatelessWidget {
  const _PortsArea(
      {required this.deviceName,
      required this.availablePorts,
      required this.onReceive,
      required this.onWrite});

  final String? deviceName;
  final List<String> availablePorts;
  final Function(String) onReceive;
  final Function(String) onWrite;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          for (final address in availablePorts)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(address,
                      style: SoftwareTextStyle().kWtMediumTextStyle),
                ),
                // Flexible(
                //   child: SizedBox(
                //     child: CustomButton(
                //       childWidget: Text(
                //         "Connect",
                //         style: SoftwareTextStyle().kBBkMediumTextStyle,
                //       ),
                //       colors: SoftwareColors.kButtonBackGroundColor,
                //       onTap: () => onReceive(address),
                //     ),
                //   ),
                // ),
                Flexible(
                  child: SizedBox(
                    child: CustomButton(
                      colors: SoftwareColors.kButtonBackGroundColor,
                      childWidget: Text(
                        "Write",
                        style: SoftwareTextStyle().kBBkMediumTextStyle,
                      ),
                      onTap: () => onWrite(address),
                    ),
                  ),
                ),
              ],
            ),
          // ValueListenableBuilder<String?>(
          //   valueListenable: deviceName,
          //   builder: (context, snapshot, _) {
          //     return snapshot != null
          //         ?
          // Card(
          //   child: Padding(
          //     padding: const EdgeInsets.all(8.0),
          //     child: Text(deviceName ?? ' '),
          //   ),
          // )
          // : const SizedBox.shrink();
          //   },
          // ),
        ],
      ),
    );
  }
}
