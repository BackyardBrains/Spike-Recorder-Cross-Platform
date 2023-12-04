import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:native_add/model/model.dart';
import 'package:provider/provider.dart';
import 'package:spikerbox_architecture/constant/const_export.dart';
import 'package:spikerbox_architecture/message_identifier.dart';
import 'package:spikerbox_architecture/models/models.dart';
import 'package:spikerbox_architecture/screen/setting_page.dart';
import '../provider/provider_export.dart';
import '../widget/widget_export.dart';
import 'graph_page_widget/sound_wave_view.dart';
import 'package:spikerbox_architecture/models/microphone_stream/microphone_stream_check.dart';

class GraphTemplate extends StatefulWidget {
  const GraphTemplate(
      {super.key,
      required this.bitsData,
      required this.channelCount,
      required this.baudRate});

  final int bitsData;
  final int channelCount;
  final int baudRate;

  @override
  State<GraphTemplate> createState() => _GraphTemplateState();
}

class _GraphTemplateState extends State<GraphTemplate> {
  List<String> _availablePorts = [];
  LocalPlugin localPlugin = LocalPlugin();
  MicrophoneUtil microphoneUtil = MicrophoneUtil();
  final double _sliderValue = 25;
  double startValue = 0;
  double endValue = 22000;
  late Ticker ticker;
  final StreamController<Uint8List> _graphStreamController = StreamController();
  late Stream<Uint8List> _graphStream;
  FilterSetup? filterBaseSettingsModel;
  List<String> connectedDevices = [];

  /// Converting bytes to uint as per custom protocol
  late BitwiseUtil _bitwiseUtil;

  /// Stream Transformer to change the values as per Custom Protocol
  late final StreamTransformer<Uint8List, Uint8List> _graphStreamTransformer;

  /// Only pauses the graph
  bool _toPauseGraph = true;
  String filterType = "";

  /// Accesses the serial port on multiple platforms
  final SerialUtil _serialUtil = SerialUtil();

  bool _isDataIdentified = false;
  late final BufferHandler _preEscapeSequenceBuffer;
  late final BufferHandler _preGraphBuffer;

  late final BufferHandler _preprocessingBuffer;

  final ValueNotifier<String?> _deviceName = ValueNotifier(null);

  late FrameDetect _frameDetect;

  final List<int> _residualBuffer = [];

  int _channelBytes = 0;
  late List<int> sumAsyncResult;

  late final MessageIdentifier _messageIdentifier;

  /// For testing keeping track of packets sent to C code
  static int packetId = 0;

  // For audio data

  static const int _sampleGeneratedCount = 1000;
  static const int timeMs = _sampleGeneratedCount ~/ dummySamplingRate * 1000;
  late final Uint8List _sampleData;
  List<SerialPortDataModel> allDevices = [];

  @override
  void didUpdateWidget(covariant GraphTemplate oldWidget) {
    super.didUpdateWidget(oldWidget);
    _frameDetect =
        FrameDetect(channelCount: widget.channelCount, minimumBytesToCheck: 50);
    _bitwiseUtil = BitwiseUtil(bitCount: widget.bitsData);
    _channelBytes = widget.channelCount * 2;
  }

  int dummyCount = 0;

  // bool isAudioListen = false;

  Future<void> _startPortCheck() async {
    Timer.periodic(const Duration(seconds: 3), (timer) async {
      int baudRate = context.read<ConstantProvider>().getBaudRate();
      _serialUtil.getAvailablePorts(baudRate);

      List<String> filteredPorts;
      if (Platform.isMacOS) {
        filteredPorts = _serialUtil.availablePorts
            .where((port) =>
                port.contains('usbmodem') || port.contains('usbserial'))
            .toList();
      } else {
        filteredPorts = _serialUtil.availablePorts;
      }

      bool isComMatch = areListsEqual(_availablePorts, filteredPorts);

      _availablePorts = filteredPorts;

      context
          .read<DataStatusProvider>()
          .setMicrophoneDataStatus(_availablePorts.isEmpty);

      if (!isComMatch) {
        Provider.of<PortScanProvider>(context, listen: false)
            .setPortScanList(_availablePorts);

        Provider.of<ConstantProvider>(context, listen: false)
            .setBaudRate(baudRate);
        allDevices = context.read<SerialDataProvider>().getAllPortDetail;
        await portListOnConnect();
      }
    });
  }

  bool areListsEqual(List<String> list1, List<String> list2) {
    if (list1.length != list2.length) {
      return false;
    }

    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) {
        return false;
      }
    }

    return true;
  }

  void setSampleRate() {
    final myDataProvider =
        Provider.of<SampleRateProvider>(context, listen: false);

    if (kIsWeb) {
      if (!mounted) return;
      myDataProvider.setSampleRate(webMicSampleRate);
    } else {
      if (Platform.isWindows) {
        if (!mounted) return;
        myDataProvider.setSampleRate(winMicSampleRate);
      } else if (Platform.isAndroid) {
        if (!mounted) return;
        myDataProvider.setSampleRate(androidMicSampleRate);
      } else if (Platform.isMacOS) {
        if (!mounted) return;
        myDataProvider.setSampleRate(macMicSampleRate);
      } else {
        if (!mounted) return;
        myDataProvider.setSampleRate(webMicSampleRate);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((timeStamp) async {
      setSampleRate();
    });
    if (!kIsWeb) {
      _startPortCheck();
    }
    filterBaseSettingsModel = const FilterSetup(
        filterConfiguration:
            FilterConfiguration(cutOffFrequency: 1000, sampleRate: 10000),
        filterType: FilterType.highPassFilter,
        channelCount: channelCountBuffer,
        isFilterOn: false);

    Future.delayed(const Duration(seconds: 2)).then((value) {
      microphoneUtil.init().then((value) {
        microphoneUtil.micStream!.listen((event) {
          bool isAudioListen =
              context.read<DataStatusProvider>().isMicrophoneData;
          // print("the event is $event");
          // isAudioListen = value;

          if (isAudioListen) {
            _preprocessingBuffer.addBytes(event);
          }
        });
      });
    });

    // TODO: remove dummy data
    _sampleData = GenerateSampleData.sineWaveUint14(
            samplingRate: dummySamplingRate,
            frequencies: [50, 1000],
            samplesGenerated: _sampleGeneratedCount)
        .buffer
        .asUint8List();

    Timer.periodic(const Duration(milliseconds: timeMs), (timer) {
      bool dummyDataStatus = context.read<DataStatusProvider>().isSampleDataOn;
      if (dummyDataStatus) {
        _preprocessingBuffer.addBytes(_sampleData);
      }
    });

    localPlugin.spawnHelperIsolate().then(
      (value) {
        localPlugin.postFilterStream?.listen((event) {
          _preGraphBuffer.addBytes(event);
        });
      },
    );
    localPlugin.initHighPassFilters(filterBaseSettingsModel!);

    _preprocessingBuffer = BufferHandler(
      chunkReadSize: 2000,
      onDataAvailable: (Uint8List listBytes) async {
        int bitData = context.read<ConstantProvider>().getBitData();

        Uint16List newDataPoints;
        Int16List int16list;
        List<int> newPoints;
        bool dummyDataStatus =
            context.read<DataStatusProvider>().isSampleDataOn;
        bool isEnableAudio =
            context.read<DataStatusProvider>().isMicrophoneData;
        if (dummyDataStatus) {
          newDataPoints = listBytes.buffer.asUint16List();
          newPoints = List.filled(newDataPoints.length, 0);
          for (int i = 0; i < newPoints.length; i++) {
            int a = 0;
            int e = newDataPoints[i];
            // a = e;
            switch (bitData) {
              case 14:
                a = e - 8192;
                // a = e;
                // print("value of a: $a, e: $e");
                break;

              case 10:
                a = (e * 30) - 15360; // (value - 512) * 30
                break;

              default:
                break;
            }
            newPoints[i] = a;
          }
        } else if (isEnableAudio) {
          int16list = dataToSamples(listBytes);
          newPoints = List.filled(int16list.length, 0);

          for (int i = 0; i < newPoints.length; i++) {
            newPoints[i] = int16list[i];
          }

          // int l = int16list.length;
          // newDataPoints = Uint16List(l);
          // for (int i = 0; i < l; i++) {
          //   newDataPoints[i] = int16list[i] + 32768;
          // }
        } else {
          int bitData = Provider.of<ConstantProvider>(context, listen: false)
              .getBitData();
          Uint8List transformedData = _bitwiseUtil.convertToValue(listBytes);
          newDataPoints = transformedData.buffer.asUint16List();
          newPoints = List.filled(newDataPoints.length, 0);

          for (int i = 0; i < newPoints.length; i++) {
            int a = 0;
            int e = newDataPoints[i];
            // a = e;

            switch (bitData) {
              case 14:
                a = e - 8192;
                // print("value of a: $a, e: $e");
                break;

              case 10:
                a = (e * 30) - 15360; // (value - 512) * 30
                break;

              default:
                break;
            }
            newPoints[i] = a;
          }
        }

        await localPlugin.filterArrayElements(
          array: newPoints,
          arrayLength: newPoints.length,
          channelIdx: 0,
        );
      },
    );

    _frameDetect =
        FrameDetect(channelCount: widget.channelCount, minimumBytesToCheck: 50);
    _bitwiseUtil = BitwiseUtil(bitCount: widget.bitsData);
    _channelBytes = widget.channelCount * 2;

    _graphStream = _graphStreamController.stream.asBroadcastStream();
    final provider = Provider.of<GraphDataProvider>(context, listen: false);

    provider.setStreamOfData(_graphStream);
    _messageIdentifier = MessageIdentifier(onDeviceData: (Uint8List dt) {
      List<int> devData = dt;

      if (_residualBuffer.isNotEmpty) {
        devData = [..._residualBuffer, ...devData];
        _residualBuffer.clear();
      }
      List<int> frameCheckedData = [];
      int i = 0;

      while (i < devData.length) {
        if (i + _channelBytes >= devData.length) {
          _residualBuffer.addAll(devData.sublist(i, devData.length));
          break;
        }
        // To check that the data received follows the Custom Protocol
        bool frameComplete = true;

        if (frameComplete) {
          checkBytesLoop:
          for (int j = 1; j < _channelBytes; j++) {
            if (!(i + j < devData.length)) break checkBytesLoop;
            if (devData.elementAt(i + j) > 127) {
              // Remaining bytes in frame are missing
              // Debugging.printing(
              //     "Remaining frame bytes missing - ${devData.sublist(i)}");
              frameComplete = false;
              break checkBytesLoop;
            }
          }
        }
        if (frameComplete) {
          frameCheckedData.addAll(devData.sublist(i, i + _channelBytes));
          i += _channelBytes;
        } else {
          i++;
          // Debugging.printing("bytes drop detected");
        }
      }
      _preprocessingBuffer.addBytes(Uint8List.fromList(frameCheckedData));
    }, onDeviceMessage: (Uint8List msg) async {
      String responseMessage =
          MessageValueSet.fromUint8ListCommand(message: msg).value;
      String? devices = checkConnectedDevices(responseMessage);

      if (devices == null) {
        return;
      }
      _deviceName.value = devices;

      SetUpFunctionality().setTheDeviceSetting(_deviceName.value).then((value) {
        String foundDevices = "";
        if (value != null) {
          foundDevices = value.uniqueName ?? "";

          Provider.of<ConstantProvider>(context, listen: false)
              .setBaudRate(foundDevices == "HHIBOX" ? 500000 : 222222);
          Provider.of<ConstantProvider>(context, listen: false)
              .setChannelCount(int.parse(value.maxNumberOfChannels.toString()));
          Provider.of<ConstantProvider>(context, listen: false)
              .setBitData(int.parse(value.sampleResolution.toString()));
          Provider.of<SampleRateProvider>(context, listen: false)
              .setSampleRate(int.parse(value.maxSampleRate.toString()));

          connectedDevices.add(foundDevices);
          SerialPortDataModel serialData = SerialPortDataModel(
              portCom: portName, deviceDetect: foundDevices);
          context.read<SerialDataProvider>().setPortOfDevices(serialData);
        }
      });
      Debugging.printing(
          "Message received from Spikerbox: \n\tbytes : $msg\n\tstring: ${String.fromCharCodes(msg)}");
    });

    _preEscapeSequenceBuffer = BufferHandler(
      chunkReadSize: 16,
      onDataAvailable: (Uint8List dataFromBuffer) {
        _messageIdentifier.addPacket(dataFromBuffer);
      },
    );

    _preGraphBuffer = BufferHandler(
      chunkReadSize: kGraphUpdateCount * 2,
      onDataAvailable: (Uint8List dataFromBuffer) {
        if (_toPauseGraph) {
          switch (widget.channelCount) {
            case 1:
              _graphStreamController.add(dataFromBuffer);
              break;

            case 2:

              // TODO: only first channel data is being passed, ie, the first two bytes
              _graphStreamController
                  .add(ChannelUtil.dropEveryOtherTwoBytes(dataFromBuffer));
              break;
          }
        }
      },
    );
  }

  static Int16List dataToSamples(Uint8List data) {
    final Int16List int16Samples = Int16List(data.length ~/ 2);
    final ByteBuffer byteBuffer = data.buffer;
    final ByteData byteData = data.buffer.asByteData();

    for (int i = 0; i < byteBuffer.lengthInBytes; i += 2) {
      int16Samples[i ~/ 2] = byteData.getInt16(i, Endian.little);
    }

    return int16Samples;
  }

  bool containsUint8List(Uint8List mainList, Uint8List subList) {
    if (mainList.length < subList.length) {
      return false; // The main list is shorter, so it can't contain the sublist.
    }

    for (int i = 0; i <= mainList.length - subList.length; i++) {
      bool found = true;

      for (int j = 0; j < subList.length; j++) {
        if (mainList[i + j] != subList[j]) {
          found = false;
          break;
        }
      }

      if (found) {
        return true; // Sublist found within the main list.
      }
    }

    return false; // Sublist not found within the main list.
  }

  // FilterSettings filterBase = FilterSettings();
  final TextEditingController sampleRateController = TextEditingController();
  final TextEditingController cutOffController = TextEditingController();

  String? checkConnectedDevices(String getResponse) {
    List<String> listOfDevices = [
      "PLANTSS;",
      "MUSCLESS;",
      "HEARTSS;",
      "HBLEOSB;",
      "HUMANSB;",
      "MSBPCDC;",
      "NSBPCDC;",
      "NRNSBPRO;",
      "HHIBOX;"
    ];

    int index = listOfDevices.indexWhere((element) => element == getResponse);
    if (index == -1) return null;
    return listOfDevices[index];
  }

  final List<int> _dataBit = [14, 10];
  final List<int> _baudRate = [222222, 230400, 500000];
  final List<int> _channelCount = [1, 2];

  String portName = "";
  bool isDeviceConnect = true;
  bool isSettingEnable = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SoftwareColors.kBackGroundColor,
      body: _AdaptiveArea(
          child1: const _GraphArea(),
          child3: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(children: [
                SpikerBoxButton(
                    onTapButton: () {
                      context
                          .read<SoftwareConfigProvider>()
                          .settingStatus(false);
                    },
                    iconData: Icons.settings),
                // const SizedBox(
                //   width: 10,
                // ),
                // Text(
                //   "Config",
                //   style: SoftwareTextStyle().kWtMediumTextStyle,
                // )
              ]),
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
                        startValue: startValue,
                        endValue: endValue,
                        sliderValue: _sliderValue,
                      ),
                      const SizedBox(
                        height: 10,
                      ),
                      NotchPassFilterWidget(
                          onTapNotchFrequency: (notchFilterSettings) {
                        print(
                            "the notch filter setting is ${notchFilterSettings.toJson()}");

                        context
                            .read<DataStatusProvider>()
                            .setNotchPassFilterSetting(notchFilterSettings);
                        localPlugin.initNotchPassFilters(notchFilterSettings);
                      }),
                      const SizedBox(
                        height: 10,
                      ),
                      Expanded(
                        child: SettingPage(
                          settingPage: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                flex: 1,
                                child: SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      FilterProcessWidget(isMicrophoneEnable:
                                          (bool isMicrophoneEnable) {
                                        // _toEnableMicrophone =
                                        //     isMicrophoneEnable;

                                        context
                                            .read<DataStatusProvider>()
                                            .setMicrophoneDataStatus(
                                                isMicrophoneEnable);
                                      }, onHighPassFilterSetup:
                                          (FilterSetup filterSetup) {
                                        localPlugin
                                            .initHighPassFilters(filterSetup);
                                      }, onLowPassFilterSetup:
                                          (FilterSetup filterSetup) {
                                        localPlugin
                                            .initLowPassFilters(filterSetup);
                                      }, onSampleChange: (bool isSampleDataOn) {
                                        context
                                            .read<DataStatusProvider>()
                                            .setSampleDataStatus(
                                                isSampleDataOn);
                                        // _toGenerateDummyData =
                                        //     isSampleDataOn;
                                      }),
                                      DropdownButtonFormField<int>(
                                        dropdownColor: SoftwareColors
                                            .kDropDownBackGroundColor,
                                        style: SoftwareTextStyle()
                                            .kWtMediumTextStyle,
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
                                          context
                                              .read<ConstantProvider>()
                                              .setBitData(bitDataSelect!);
                                        },
                                        value: context
                                            .read<ConstantProvider>()
                                            .getBitData(),
                                      ),
                                      DropdownButtonFormField(
                                        dropdownColor: SoftwareColors
                                            .kDropDownBackGroundColor,
                                        style: SoftwareTextStyle()
                                            .kWtMediumTextStyle,
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
                                          context
                                              .read<ConstantProvider>()
                                              .setBaudRate(baudRateSelect!);
                                        },
                                        value: context
                                            .read<ConstantProvider>()
                                            .getBaudRate(),
                                      ),
                                      DropdownButtonFormField(
                                        dropdownColor: SoftwareColors
                                            .kDropDownBackGroundColor,
                                        style: SoftwareTextStyle()
                                            .kWtMediumTextStyle,
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
                                          context
                                              .read<ConstantProvider>()
                                              .setChannelCount(
                                                  channelCountSelect!);
                                        },
                                        value: context
                                            .read<ConstantProvider>()
                                            .getChannelCount(),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Consumer<PortScanProvider>(
                                    builder: (context, portList, snapshot) {
                                  return _PortsArea(
                                    deviceName: _deviceName,
                                    availablePorts: portList.availablePorts,
                                    onReceive: (String add) async {
                                      // int baudRate = context
                                      //     .read<ConstantProvider>()
                                      //     .getBaudRate();

                                      // await _serialUtil.openPortToListen(
                                      //     add, baudRate);

                                      // // ignore: use_build_context_synchronously
                                      // context
                                      //     .read<DataStatusProvider>()
                                      //     .setMicrophoneDataStatus(false);

                                      // if (!mounted) return;
                                      // bool dummyDataStatus = context
                                      //     .read<DataStatusProvider>()
                                      //     .isSampleDataOn;
                                      // bool isAudioListen = context
                                      //     .read<DataStatusProvider>()
                                      //     .isMicrophoneData;
                                      // try {
                                      //   _serialUtil.dataStream?.listen((event) {
                                      //     if (!dummyDataStatus &&
                                      //         !isAudioListen) {
                                      //       _preEscapeSequenceBuffer
                                      //           .addBytes(event);
                                      //       if (isDeviceConnect) {
                                      //         _serialUtil.writeToPort(
                                      //             bytesMessage: UsbCommand
                                      //                 .hwTypeInquiry
                                      //                 .cmdAsBytes(),
                                      //             address: add);

                                      //         isDeviceConnect = false;
                                      //       }
                                      //       if (_isDataIdentified) {
                                      //         // Debugging.printing('us: ${stopwatch.elapsedMicroseconds}, length : ${event.length}');
                                      //         // stopwatch.reset();
                                      //       } else {
                                      //         Uint8List? firstFrameData =
                                      //             _frameDetect.addData(event);

                                      //         if (firstFrameData != null) {
                                      //           _preEscapeSequenceBuffer
                                      //               .addBytes(firstFrameData);
                                      //           _isDataIdentified = true;
                                      //         }
                                      //       }
                                      //     }
                                      //   });
                                      //   portName = add;
                                      // } catch (e) {
                                      //   print(
                                      //       "the error is $e from serial port");
                                      // }
                                    },
                                    onWrite: (String add) async {
                                      MessageValueSet? selectedCommand =
                                          await showCommandPopUp(add);
                                      if (selectedCommand != null) {
                                        _serialUtil.writeToPort(
                                            bytesMessage:
                                                selectedCommand.cmdAsBytes(),
                                            address: add);
                                      }
                                    },
                                  );
                                }),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          child2: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      SpikerBoxButton(
                          onTapButton: () async {
                            context
                                .read<SoftwareConfigProvider>()
                                .settingStatus(true);
                          },
                          iconData: Icons.settings),
                      const SizedBox(
                        width: 10,
                      ),
                      // SpikerBoxButton(
                      //     onTapButton: () async {}, iconData: Icons.graphic_eq),
                      // const SizedBox(
                      //   width: 10,
                      // ),
                      SpikerBoxButton(
                        onTapButton: () {},
                        iconData: Icons.graphic_eq_outlined,
                      ),
                      const SizedBox(
                        width: 10,
                      ),
                      StreamBuilder<List<ComDataWithBoard>>(
                          stream: connectDeviceList(),
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              List<ComDataWithBoard> listOfBoard =
                                  snapshot.data!;

                              return SizedBox(
                                height: 50,
                                child: ListView.builder(
                                    padding: EdgeInsets.zero,
                                    scrollDirection: Axis.horizontal,
                                    shrinkWrap: true,
                                    itemCount: listOfBoard.length,
                                    itemBuilder: (context, index) {
                                      return GestureDetector(
                                        onTap: () {
                                          Provider.of<ConstantProvider>(context,
                                                  listen: false)
                                              .setBaudRate(int.parse(
                                                  listOfBoard[index]
                                                      .connectDevices
                                                      .maxSampleRate
                                                      .toString()));
                                          Provider.of<ConstantProvider>(context,
                                                  listen: false)
                                              .setChannelCount(int.parse(
                                                  listOfBoard[index]
                                                      .connectDevices
                                                      .maxNumberOfChannels
                                                      .toString()));
                                          Provider.of<ConstantProvider>(context,
                                                  listen: false)
                                              .setBitData(int.parse(
                                                  listOfBoard[index]
                                                      .connectDevices
                                                      .sampleResolution
                                                      .toString()));
                                        },
                                        child: SpikerBoxButton(
                                            onTapButton: () {},
                                            iconData: Icons.usb),
                                      );
                                    }),
                              );
                            } else {
                              return Container();
                            }
                          })
                    ],
                  ),
                  Row(
                    children: [
                      SpikerBoxButton(
                        onTapButton: () {},
                        iconData: Icons.fiber_manual_record,
                        iconColor: Colors.red,
                      ),
                      const SizedBox(
                        width: 10,
                      ),
                      SpikerBoxButton(onTapButton: () {}, iconData: Icons.menu)
                    ],
                  )
                ],
              ),
              BottomButtons(
                pauseButton: (bool isPlay) {
                  Provider.of<GraphResumePlayProvider>(context, listen: false)
                      .setGraphResumePlay(isPlay);
                  _toPauseGraph = isPlay;
                },
              ),
            ],
          )),
      floatingActionButton: kIsWeb
          ? FloatingActionButton.extended(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                  side: const BorderSide(width: 2, color: Colors.grey)),
              backgroundColor: SoftwareColors.kButtonBackGroundColor,
              onPressed: () async {
                try {
                  int baudRate = context.read<ConstantProvider>().getBaudRate();
                  await _serialUtil.getAvailablePorts(baudRate);
                  _availablePorts = _serialUtil.availablePorts;
                  if (!mounted) return;
                  Provider.of<PortScanProvider>(context, listen: false)
                      .setPortScanList(_availablePorts);
                  context
                      .read<DataStatusProvider>()
                      .setMicrophoneDataStatus(false);

                  // await _serialUtil.openPortToListen(
                  //     _availablePorts.first, baudRate);

                  if (!mounted) return;
                  bool dummyDataStatus =
                      context.read<DataStatusProvider>().isSampleDataOn;
                  bool isAudioListen =
                      context.read<DataStatusProvider>().isMicrophoneData;

                  _serialUtil.dataStream?.listen((event) {
                    if (!dummyDataStatus && !isAudioListen) {
                      _preEscapeSequenceBuffer.addBytes(event);
                      if (isDeviceConnect) {
                        _serialUtil.writeToPort(
                            bytesMessage: UsbCommand.hwTypeInquiry.cmdAsBytes(),
                            address: _availablePorts.last);

                        isDeviceConnect = false;
                      }

                      if (_isDataIdentified) {
                        // Debugging.printing('us: ${stopwatch.elapsedMicroseconds}, length : ${event.length}');
                        // stopwatch.reset();
                      } else {
                        Uint8List? firstFrameData = _frameDetect.addData(event);

                        if (firstFrameData != null) {
                          _preEscapeSequenceBuffer.addBytes(firstFrameData);
                          _isDataIdentified = true;
                        }
                      }
                    }
                  });
                  portName = _availablePorts.first;
                } catch (e) {
                  Debugging.printing("Opening port failed:\n$e");
                }

                setState(() {});
              },
              label: Row(
                children: [
                  Text(
                    "Scan port",
                    style: SoftwareTextStyle().kBkMediumTextStyle,
                  ),
                  Icon(
                    Icons.refresh,
                    color: SoftwareColors.kButtonColor,
                  )
                ],
              ),
            )
          : Container(),
    );
  }

  Stream<List<ComDataWithBoard>>? connectDeviceList() {
    // Create a stream controller to manage the stream
    StreamController<List<ComDataWithBoard>> deviceListStream =
        StreamController<List<ComDataWithBoard>>();

    // Obtain the stream from the stream controller
    Stream<List<ComDataWithBoard>>? deviceList =
        deviceListStream.stream.asBroadcastStream();

    // Stream<List<ComDataWithBoard>>? deviceList;
    // Call the asynchronous function to get all device lists
    if (connectedDevices.isNotEmpty) {
      SetUpFunctionality().getAllDeviceList().then((value) {
        // Extract the list of boards from the result
        List<Board> allBoards = value.boards ?? [];
        // Filter the boards based on some condition (e.g., matching unique names)
        List<Board> connectedBoards = allBoards.where((board) {
          return connectedDevices.contains(board.uniqueName);
        }).toList();

        // Add the filtered list to the stream
        List<ComDataWithBoard> deviceDataWithCom =
            createComDataWithBoardList(connectedBoards, allDevices);
        deviceListStream.add(deviceDataWithCom);

        // Print the stream (optional)
      });
    } else {
      return null;
    }

    // Return the broadcast stream
    return deviceList;
  }

  List<ComDataWithBoard> createComDataWithBoardList(
      List<Board> connectedBoards, List<SerialPortDataModel> allDevices) {
    List<ComDataWithBoard> result = [];

    for (SerialPortDataModel device in allDevices) {
      Board matchingBoard = connectedBoards.firstWhere(
        (board) => board.uniqueName == device.deviceDetect,
        orElse: () => Board(
            /* Default values or handle the case when no match is found */),
      );

      ComDataWithBoard comDataWithBoard = ComDataWithBoard(
        connectDevices: matchingBoard,
        serialPortData: device,
      );

      result.add(comDataWithBoard);
    }

    return result;
  }

  Future<void> portListOnConnect() async {
    DataStatusProvider dataStatus = context.read<DataStatusProvider>();
    List<String> listOfPort =
        Provider.of<PortScanProvider>(context, listen: false).availablePorts;
    int baudRate = context.read<ConstantProvider>().getBaudRate();
    if (listOfPort.isEmpty) {
      return;
    }
    Stream<Uint8List>? getData =
        await _serialUtil.openPortToListen(listOfPort.last, baudRate);

    bool dummyDataStatus = dataStatus.isSampleDataOn;
    bool isAudioListen = dataStatus.isMicrophoneData;
    dataStatus.setDeviceDataStatus(true);

    Stopwatch stopwatch = Stopwatch();
    getData?.listen((event) {
      stopwatch.start();
      if (!dummyDataStatus && !isAudioListen) {
        _preEscapeSequenceBuffer.addBytes(event);
        // print(
        //     "the time taken is ${stopwatch.elapsedMilliseconds}and the length ${event.length}");
        stopwatch.reset();
        if (isDeviceConnect) {
          _serialUtil.writeToPort(
              bytesMessage: UsbCommand.hwTypeInquiry.cmdAsBytes(),
              address: listOfPort.last);

          isDeviceConnect = false;
        }
        if (_isDataIdentified) {
          // Debugging.printing('us: ${stopwatch.elapsedMicroseconds}, length : ${event.length}');
          // stopwatch.reset();
        } else {
          Uint8List? firstFrameData = _frameDetect.addData(event);

          if (firstFrameData != null) {
            _preEscapeSequenceBuffer.addBytes(firstFrameData);
            _isDataIdentified = true;
          }
        }
      }
    });
    portName = listOfPort.last;
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

    _notchPassFilterSettings = FilterSetup(
        filterConfiguration: FilterConfiguration(
            cutOffFrequency: 50, sampleRate: _sampleRate.toInt()),
        filterType: FilterType.notchFilter,
        channelCount: channelCountBuffer,
        isFilterOn: false);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<SampleRateProvider, DataStatusProvider>(
        builder: (context, sampleRate, dataStatus, snapshot) {
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
                  if (isNotch60) {
                    dataStatus.set60HertzStatus(false);

                    isNotch50 = value!;
                  } else {
                    isNotch50 = value!;
                  }
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

// ignore: must_be_immutable
class WhiteColorCheckBox extends StatefulWidget {
  WhiteColorCheckBox(
      {required this.valueStatus, super.key, required this.onChanged});

  bool? valueStatus;
  final Function(bool?) onChanged;

  @override
  State<WhiteColorCheckBox> createState() => _WhiteColorCheckBoxState();
}

class _WhiteColorCheckBoxState extends State<WhiteColorCheckBox> {
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(unselectedWidgetColor: Colors.white),
      child: Checkbox(
        activeColor: SoftwareColors.kGraphColor,
        checkColor: Colors.white,
        onChanged: widget.onChanged,
        value: widget.valueStatus,
      ),
    );
  }
}

class SetFrequencyWidget extends StatelessWidget {
  const SetFrequencyWidget({
    super.key,
    required this.frequencyType,
    required this.frequencyValue,
  });
  final int frequencyValue;
  final String frequencyType;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          frequencyType,
          style: SoftwareTextStyle().kWtMediumTextStyle,
        ),
        DecoratedBox(
            decoration: BoxDecoration(
                border: Border.all(width: 1, color: Colors.white)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 2),
              child: Text(
                frequencyValue.toString(),
                style: SoftwareTextStyle().kWtMediumTextStyle,
              ),
            ))
      ],
    );
  }
}

class _AdaptiveArea extends StatefulWidget {
  const _AdaptiveArea(
      {required this.child1, required this.child3, required this.child2});

  final Widget child1;
  final Widget child2;
  final Widget child3;

  @override
  State<_AdaptiveArea> createState() => _AdaptiveAreaState();
}

class _AdaptiveAreaState extends State<_AdaptiveArea> {
  @override
  Widget build(BuildContext context) {
    return Consumer<SoftwareConfigProvider>(
        builder: (context, softwareSetting, snapshot) {
      return SizedBox.expand(
        child: Stack(
          children: [
            widget.child1,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
              child: widget.child2,
            ),
            softwareSetting.isSettingEnable
                ? Container(
                    color: Colors.black54.withOpacity(0.9),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 15),
                      child: widget.child3,
                    ),
                  )
                : Container()
          ],
        ),
      );
    });
  }
}

class _GraphArea extends StatefulWidget {
  const _GraphArea();

  // final Function(bool isPlay) onPause;

  @override
  State<_GraphArea> createState() => _GraphAreaState();
}

class _GraphAreaState extends State<_GraphArea> {
  List<String> listOfFrequency = ["40 Hz", "30 Hz", "20 Hz", "10 Hz"];
  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Expanded(
          flex: 6,
          child: SoundWaveView(),
        ),
      ],
    );
  }
}

class _PortsArea extends StatelessWidget {
  const _PortsArea(
      {required this.deviceName,
      required this.availablePorts,
      required this.onReceive,
      required this.onWrite});

  final ValueNotifier<String?> deviceName;
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
          ValueListenableBuilder<String?>(
            valueListenable: deviceName,
            builder: (context, snapshot, _) {
              return snapshot != null
                  ? Card(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(snapshot),
                      ),
                    )
                  : const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }
}

class FilterProcessWidget extends StatefulWidget {
  const FilterProcessWidget({
    super.key,
    required this.onHighPassFilterSetup,
    required this.onLowPassFilterSetup,
    required this.onSampleChange,
    required this.isMicrophoneEnable,
  });

  final Function(bool) isMicrophoneEnable;
  final Function(bool) onSampleChange;
  final Function(FilterSetup) onHighPassFilterSetup;
  final Function(FilterSetup) onLowPassFilterSetup;

  @override
  State<FilterProcessWidget> createState() => _FilterProcessWidgetState();
}

class _FilterProcessWidgetState extends State<FilterProcessWidget> {
  MicrophoneUtil microphoneUtil = MicrophoneUtil();
  bool _isSampleDataOn = false;
  bool _isMicrophoneEnable = false;
  final TextEditingController _lowSampleRateController =
      TextEditingController();
  final TextEditingController _lowCutOffController = TextEditingController();
  final TextEditingController _highSampleRateController =
      TextEditingController();
  final TextEditingController _highCutOffController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _lowCutOffController.dispose();
    _lowSampleRateController.dispose();
    _highCutOffController.dispose();
    _highSampleRateController.dispose();
    super.dispose();
  }

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
                  setState(() {
                    _isSampleDataOn = value ?? false;
                    if (_isSampleDataOn && _isMicrophoneEnable) {
                      _isMicrophoneEnable = false;
                      widget.isMicrophoneEnable(_isMicrophoneEnable);
                    }
                  });
                  Provider.of<SampleRateProvider>(context, listen: false)
                      .setSampleRate(dummySamplingRate);
                  widget.onSampleChange(_isSampleDataOn);
                },
              ),
              Text(
                "Sample Data ",
                style: SoftwareTextStyle().kWtMediumTextStyle,
              )
            ],
          ),
          const SizedBox(height: 10),
          // CustomButton(
          //   childWidget: const Text("Check audio on web"),
          //   onTap: () async {},
          // ),
          Row(
            children: [
              WhiteColorCheckBox(
                valueStatus: dataStatus.isMicrophoneData,
                onChanged: (value) {
                  setState(() {
                    _isMicrophoneEnable = value ?? false;
                    if (_isMicrophoneEnable && _isSampleDataOn) {
                      _isSampleDataOn = false;
                      widget.onSampleChange(_isSampleDataOn);
                    }
                  });
                  widget.isMicrophoneEnable(_isMicrophoneEnable);
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
