import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:native_add/model/model.dart';
import 'package:provider/provider.dart';
import 'package:spikerbox_architecture/constant/const_export.dart';
import 'package:spikerbox_architecture/functionality/functionality_export.dart';
import 'package:spikerbox_architecture/message_identifier.dart';
import 'package:spikerbox_architecture/models/global_buffer.dart';
import 'package:spikerbox_architecture/models/models.dart';
import 'package:spikerbox_architecture/screen/setting_buttons.dart';
import 'package:spikerbox_architecture/screen/setting_page.dart';
import '../provider/provider_export.dart';
import 'graph_page_widget/sound_wave_view.dart';
import 'package:spikerbox_architecture/models/microphone_stream/microphone_stream_check.dart';

class GraphTemplate extends StatefulWidget {
  const GraphTemplate({
    super.key,
    required this.constantProvider,
  });
  final ConstantProvider constantProvider;

  @override
  State<GraphTemplate> createState() => _GraphTemplateState();
}

class _GraphTemplateState extends State<GraphTemplate> {
  List<String> _availablePorts = [];

  MicrophoneUtil microphoneUtil = MicrophoneUtil();
  final StreamController<Uint8List> _graphStreamController = StreamController();
  late Stream<Uint8List> _graphStream;
  FilterSetup? filterBaseSettingsModel;
  DebugTimeProvider debugTimeCalculate = DebugTimeProvider();

  /// Converting bytes to uint as per custom protocol
  late BitwiseUtil _bitwiseUtil;

  DeviceStatusFunctionality deviceStatusFunctionality =
      DeviceStatusFunctionality();

  /// Only pauses the graph
  bool _toPauseGraph = true;

  /// Accesses the serial port on multiple platforms
  late final BufferHandler _preGraphBuffer;

  late final BufferHandler _preprocessingBuffer;

  final List<int> _residualBuffer = [];

  int _channelBytes = 0;
  late final MessageIdentifier _messageIdentifier;

  // For audio data
  static const int _sampleGeneratedCount = 1000;
  static const int timeMs = _sampleGeneratedCount ~/ dummySamplingRate * 1000;
  late final Uint8List _sampleData;

  @override
  void didUpdateWidget(covariant GraphTemplate oldWidget) {
    super.didUpdateWidget(oldWidget);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      frameDetect = FrameDetect(
          channelCount: widget.constantProvider.getChannelCount(),
          minimumBytesToCheck: 50);
      _bitwiseUtil =
          BitwiseUtil(bitCount: widget.constantProvider.getBitData());
      _channelBytes = widget.constantProvider.getChannelCount() * 2;
    });
  }

  bool isAudioListen = false;
  Stopwatch timeTaken = Stopwatch();
  int dummyCount = 0;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      setBufferSetting(webMicSampleRate);
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) async {
        setSampleRate();
      });
    }
    if (!kIsWeb) {
      _startPortCheck();
    }

    Provider.of<GraphResumePlayProvider>(context, listen: false)
        .getStream()
        .listen((event) {
      _toPauseGraph = event;
    });

    Future.delayed(const Duration(seconds: 2)).then((value) {
      microphoneUtil.init().then((value) {
        microphoneUtil.micStream!.listen((event) {
          // print("the length of ${event.length}");
          isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
          // print("the event is $event");
          // isAudioListen = value;

          if (isAudioListen) {
            _preprocessingBuffer.addBytes(event);
          }
        });
        // if (!kIsWeb) {
        //   microphoneUtil.packetAddDetail!.listen((event) {
        //     if (isAudioListen) {
        //       AudioDetail audioDetail = AudioDetail(
        //           avgTime: event.averageTime,
        //           maxTime: event.maxTime,
        //           minTime: event.minTime);
        //       context.read<DebugTimeProvider>().setAudioDetail(audioDetail);
        //     }
        //   });
        // }
      });
    });

    // TODO: remove dummy data
    _sampleData = GenerateSampleData.sineWaveUint14(
            samplingRate: dummySamplingRate,
            frequencies: [60],
            samplesGenerated: _sampleGeneratedCount)
        .buffer
        .asUint8List();

    Timer.periodic(const Duration(milliseconds: timeMs), (timer) {
      bool dummyDataStatus = context.read<DataStatusProvider>().isSampleDataOn;
      if (dummyDataStatus) {
        _preprocessingBuffer.addBytes(_sampleData);
      }
    });
    filterBaseSettingsModel = const FilterSetup(
        filterConfiguration:
            FilterConfiguration(cutOffFrequency: 1000, sampleRate: 10000),
        filterType: FilterType.highPassFilter,
        channelCount: channelCountBuffer,
        isFilterOn: false);

    localPlugin.spawnHelperIsolate().then(
      (value) {
        timeTaken.start();
        localPlugin.postFilterStream?.listen((event) {
          if (isDebugging) {
            context
                .read<DebugTimeProvider>()
                .addGraphTime(timeTaken.elapsedMicroseconds);
            timeTaken.reset();
          }

          passingDataToStream(event);

          // _preGraphBuffer.addBytes(event);
        });
      },
    );

    localPlugin.initHighPassFilters(filterBaseSettingsModel!);

    _preprocessingBuffer = BufferHandler(
      chunkReadSize: 2000,
      onDataAvailable: (Uint8List listBytes) async {
        int bitData = context.read<ConstantProvider>().getBitData();
        DataStatusProvider dataStatusProvider =
            context.read<DataStatusProvider>();
        isDebugging = dataStatusProvider.isDebugging;

        Uint16List newDataPoints;
        Int16List int16list;
        List<int> newPoints;

        bool dummyDataStatus = dataStatusProvider.isSampleDataOn;
        bool isEnableAudio = dataStatusProvider.isMicrophoneData;
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
          print("the list bytes of ${listBytes.length}");
          int16list = dataToSamples(listBytes);
          print("the length is ${int16list.length}");
          newPoints = List.filled(int16list.length, 0);

          for (int i = 0; i < newPoints.length; i++) {
            newPoints[i] = int16list[i];
          }
        } else {
          int bitData = widget.constantProvider.getBitData();
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

    frameDetect = FrameDetect(
        channelCount: widget.constantProvider.getChannelCount(),
        minimumBytesToCheck: 50);

    _bitwiseUtil = BitwiseUtil(bitCount: widget.constantProvider.getBitData());
    _channelBytes = widget.constantProvider.getChannelCount() * 2;

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

      SetUpFunctionality().setTheDeviceSetting(devices).then((value) {
        String foundDevices = "";
        if (value != null) {
          print("the found ${value.uniqueName} and  $devices");
          isDeviceConnect = true;
          foundDevices = value.uniqueName ?? "";
          context.read<PortScanProvider>().setDeviceList(foundDevices);
          widget.constantProvider
              .setBaudRate(foundDevices == "HHIBOX" ? 500000 : 222222);
          widget.constantProvider
              .setChannelCount(int.parse(value.maxNumberOfChannels.toString()));
          widget.constantProvider
              .setBitData(int.parse(value.sampleResolution.toString()));
          Provider.of<SampleRateProvider>(context, listen: false)
              .setSampleRate(int.parse(value.maxSampleRate.toString()));
          // Provider.of<GraphDataProvider>(context, listen: false)
          //     .setBufferLength(int.parse(value.maxSampleRate.toString()));

          SerialPortDataModel serialData = SerialPortDataModel(
              portCom: portName, deviceDetect: foundDevices);
          context.read<SerialDataProvider>().setPortOfDevices(serialData);

          deviceConnectedStream();
        }
      });
      Debugging.printing(
          "Message received from Spikerbox: \n\tbytes : $msg\n\tstring: ${String.fromCharCodes(msg)}");
    });

    preEscapeSequenceBuffer = BufferHandler(
      chunkReadSize: 16,
      onDataAvailable: (Uint8List dataFromBuffer) {
        _messageIdentifier.addPacket(dataFromBuffer);
      },
    );

    _preGraphBuffer = BufferHandler(
      chunkReadSize: kGraphUpdateCount * 2,
      onDataAvailable: (Uint8List dataFromBuffer) {
        if (kIsWeb) {
          switch (widget.constantProvider.getChannelCount()) {
            case 1:
              _graphStreamController.add(dataFromBuffer);
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

  String portName = "";
  bool isDeviceConnect = false;
  bool isSettingEnable = false;
  bool isDebugging = false;

  void passingDataToStream(Uint8List uint8list) {
    if (_toPauseGraph) {
      // if (kIsWeb) {
      //   _preGraphBuffer.addBytes(uint8list);
      // } else {
      _graphStreamController.add(uint8list);
      // }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SoftwareColors.kBackGroundColor,
      body: const _AdaptiveArea(
        child1: _GraphArea(),
        child3: SettingPage(),
        child2: SettingButtons(),
      ),
      floatingActionButton: kIsWeb
          ? FloatingActionButton.extended(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                  side: const BorderSide(width: 2, color: Colors.grey)),
              backgroundColor: SoftwareColors.kButtonBackGroundColor,
              onPressed: () async {
                SerialUtil? _serialUtil = SerialUtil();
                try {
                  int baudRate = context.read<ConstantProvider>().getBaudRate();
                  await listenPort?.cancel();

                  await _serialUtil.getAvailablePorts(baudRate);
                  _availablePorts = _serialUtil.availablePorts;
                  print("the serial ports is $_availablePorts");
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
                  // _serialUtil.deviceConnectWithPort();
                  listenPort = _serialUtil.dataStream?.listen((event) {
                    if (!dummyDataStatus && !isAudioListen) {
                      preEscapeSequenceBuffer.addBytes(event);
                      if (!isDeviceConnect) {
                        serialUtil.writeToPort(
                            bytesMessage: UsbCommand.hwTypeInquiry.cmdAsBytes(),
                            address: _availablePorts.last);
                        isDeviceConnect = true;
                      }

                      if (isDataIdentified) {
                        // Debugging.printing('us: ${stopwatch.elapsedMicroseconds}, length : ${event.length}');
                        // stopwatch.reset();
                      } else {
                        Uint8List? firstFrameData = frameDetect.addData(event);

                        if (firstFrameData != null) {
                          preEscapeSequenceBuffer.addBytes(firstFrameData);
                          isDataIdentified = true;
                        }
                      }
                    }
                  });
                } catch (e) {
                  Debugging.printing("Opening port failed:\n$e");
                }

                // setState(() {});
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

  void deviceConnectedStream() {
    SerialDataProvider serialDataProvider = context.read<SerialDataProvider>();

    List<SerialPortDataModel> allDevices = serialDataProvider.getAllPortDetail;
    List<String> connectedDevices = [];
    connectedDevices = List.from(context.read<PortScanProvider>().deviceList);

    Set<String> uniqueDevices = Set.from(connectedDevices);
    //  Convert the Set back to a List
    List<String> uniqueConnectedDevices = List.from(uniqueDevices);

    deviceStatusFunctionality.connectDeviceList(
        uniqueConnectedDevices, allDevices, serialDataProvider);
  }

  Future<void> _startPortCheck() async {
    Timer.periodic(const Duration(seconds: 3), (timer) async {
      SampleRateProvider sampleRateProvider =
          context.read<SampleRateProvider>();

      serialUtil.getAvailablePorts(widget.constantProvider.getBaudRate());
      if (serialUtil.availablePorts.isEmpty) {
        return;
      }
      if (serialUtil.availablePorts.isEmpty) {
        isDeviceConnect = false;
      }

      List<String> filteredPorts;
      if (Platform.isMacOS) {
        filteredPorts = serialUtil.availablePorts
            .where((port) =>
                port.contains('usbmodem') || port.contains('usbserial'))
            .toList();
      } else {
        filteredPorts = serialUtil.availablePorts;
      }
      bool isComMatch = areListsEqual(_availablePorts, filteredPorts);
      _availablePorts = filteredPorts;
// All time getting true
      context
          .read<DataStatusProvider>()
          .setMicrophoneDataStatus(_availablePorts.isEmpty);

      if (isComMatch == false) {
        await serialUtil.deviceConnectWithPort(
            sampleRateProvider, widget.constantProvider);
        isDeviceConnect = false;
        Provider.of<PortScanProvider>(context, listen: false)
            .setPortScanList(_availablePorts);
        Provider.of<ConstantProvider>(context, listen: false)
            .setBaudRate(widget.constantProvider.getBaudRate());
        await portListOnConnect();
      }
    });
  }

  bool areListsEqual(List<String> list1, List<String> list2) {
    if (list1.length > list2.length) {
      List<SerialPortDataModel> allDevices =
          List.from(context.read<SerialDataProvider>().getAllPortDetail);

      allDevices.removeWhere((element) => !list2.contains(element.portCom));
      Debugging.printing(
          "the element is remove  left${allDevices.map((e) => e.portCom)}");
      List<String> connectDevice =
          List.from(context.read<PortScanProvider>().deviceList);
      connectDevice.removeWhere(
          (element) => allDevices.any((e) => e.deviceDetect != element));

      for (SerialPortDataModel element in allDevices) {
        context.read<SerialDataProvider>().setPortOfDevices(element);
      }
      List<ComDataWithBoard> deviceComWithData =
          List.from(context.read<SerialDataProvider>().deviceWithComData);
      deviceComWithData.removeWhere((element) =>
          !connectDevice.contains(element.connectDevices.uniqueName));

// Step 2: Create a new list without the removed elements
      List<ComDataWithBoard> updatedDeviceComWithData =
          List.from(deviceComWithData);

      Debugging.printing(
          "the updated List deviceComWithData  ${updatedDeviceComWithData.map((e) => e.connectDevices.uniqueName)}");

      // context
      //     .read<SerialDataProvider
// Step 3: Iterate over the updated list and perform necessary actions
      context
          .read<SerialDataProvider>()
          .setDeviceWithComData(updatedDeviceComWithData);
      return true;
    }
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
    if (Platform.isWindows) {
      setBufferSetting(winMicSampleRate);
    } else if (Platform.isAndroid) {
      setBufferSetting(androidMicSampleRate);
    } else if (Platform.isMacOS) {
      setBufferSetting(macMicSampleRate);
    }
  }

  void setBufferSetting(int sampleRate) {
    print("the sample Rate is $sampleRate");
    final myDataProvider =
        Provider.of<SampleRateProvider>(context, listen: false);
    myDataProvider.setSampleRate(sampleRate);

    // final dataStatusProvider =
    //     Provider.of<GraphDataProvider>(context, listen: false);
    // dataStatusProvider.setBufferLength(webMicSampleRate * 30);
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
        await serialUtil.openPortToListen(listOfPort.last, baudRate);

    bool dummyDataStatus = dataStatus.isSampleDataOn;
    bool isAudioListen = dataStatus.isMicrophoneData;
    dataStatus.setDeviceDataStatus(true);

    await listenPort?.cancel();
    Stopwatch stopwatch = Stopwatch();
    listenPort = getData?.listen((event) {
      stopwatch.start();
      if (!dummyDataStatus && !isAudioListen) {
        preEscapeSequenceBuffer.addBytes(event);
        // print(
        //     "the time taken is ${stopwatch.elapsedMilliseconds}and the length ${event.length}");

        if (!isDeviceConnect) {
          serialUtil.writeToPort(
              bytesMessage: UsbCommand.hwTypeInquiry.cmdAsBytes(),
              address: listOfPort.last);
          isDeviceConnect = true;
        }
        if (isDataIdentified) {
          // Debugging.printing('us: ${stopwatch.elapsedMicroseconds}, length : ${event.length}');
          // stopwatch.reset();
        } else {
          Uint8List? firstFrameData = frameDetect.addData(event);

          if (firstFrameData != null) {
            preEscapeSequenceBuffer.addBytes(firstFrameData);
            isDataIdentified = true;
          }
        }
      }
    });
    portName = listOfPort.last;
  }
}

class SetFrequencyWidget extends StatefulWidget {
  const SetFrequencyWidget({
    super.key,
    required this.frequencyType,
    required this.frequencyValue,
    required this.frequencyEditController,
    required this.onStringChanged,
  });
  final int frequencyValue;
  final TextEditingController frequencyEditController;
  final String frequencyType;
  final Function(String) onStringChanged;

  @override
  State<SetFrequencyWidget> createState() => _SetFrequencyWidgetState();
}

class _SetFrequencyWidgetState extends State<SetFrequencyWidget> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          widget.frequencyType,
          style: SoftwareTextStyle().kWtMediumTextStyle,
        ),
        SizedBox(
          width: 50,
          height: 35,
          child: DecoratedBox(
              decoration: BoxDecoration(
                  border: Border.all(width: 1, color: Colors.white)),
              child: Center(
                child: TextFormField(
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                  ],
                  onChanged: widget.onStringChanged,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.all(2),
                    border: InputBorder.none,
                  ),
                  style: SoftwareTextStyle().kWtMediumTextStyle,
                  controller: widget.frequencyEditController,
                ),
              )),
        )
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
    return SizedBox.expand(
      child: Stack(
        children: [
          widget.child1,
          StreamListenerWidget(child2: widget.child2),
          DeviceSettingConfiguration(
            child3: widget.child3,
          )
        ],
      ),
    );
  }
}

class StreamListenerWidget extends StatefulWidget {
  const StreamListenerWidget({super.key, required this.child2});

  final Widget child2;

  @override
  State<StreamListenerWidget> createState() => _StreamListenerWidgetState();
}

class _StreamListenerWidgetState extends State<StreamListenerWidget> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
      child: widget.child2,
    );
  }
}

class DeviceSettingConfiguration extends StatefulWidget {
  const DeviceSettingConfiguration({super.key, required this.child3});

  final Widget child3;

  @override
  State<DeviceSettingConfiguration> createState() =>
      _DeviceSettingConfigurationState();
}

class _DeviceSettingConfigurationState
    extends State<DeviceSettingConfiguration> {
  @override
  Widget build(BuildContext context) {
    return Consumer<SoftwareConfigProvider>(
        builder: (context, softwareSetting, snapshot) {
      if (softwareSetting.isSettingEnable) {
        return Container(
          color: Colors.black54.withOpacity(0.9),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
            child: widget.child3,
          ),
        );
      }
      return const SizedBox.shrink();
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
