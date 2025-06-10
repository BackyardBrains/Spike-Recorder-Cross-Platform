import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:mic_stream/mic_stream.dart';
// import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:native_add/model/model.dart';
import 'package:provider/provider.dart';
import 'package:spikerbox_architecture/constant/const_export.dart';
import 'package:spikerbox_architecture/functionality/utils.dart';
import 'package:spikerbox_architecture/message_identifier.dart';
import 'package:spikerbox_architecture/models/models.dart';
import 'package:spikerbox_architecture/models/processing_utils/processing_util.dart';
import 'package:spikerbox_architecture/screen/setting_page.dart';
import 'package:spikerbox_architecture/screen/spiker_box_ui.dart';
import '../provider/provider_export.dart';
import '../widget/widget_export.dart';
import 'graph_page_widget/sound_wave_view.dart';
import 'package:spikerbox_architecture/models/microphone_stream/microphone_stream_check.dart';

class GraphTemplate extends StatefulWidget {
  static bool isPlayerPaused = false;
  static Board? selectedBoard;
  const GraphTemplate({super.key, required this.bitsData, required this.channelCount, required this.baudRate});

  final int bitsData;
  final int channelCount;
  final int baudRate;
  @override
  State<GraphTemplate> createState() => _GraphTemplateState();
}

class _GraphTemplateState extends State<GraphTemplate> {
  List<double> bufferPos = [0, 0];

  var envelopeSizes = [];
  List<int> skipCounts = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512];
  List<int> arrCounts = [ 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048 ];

  List<String> listOfDevices = ["PLANTSS;", "MUSCLESS;", "HEARTSS;", "HBLEOSB;", "HUMANSB;", "MSBPCDC;", "NSBPCDC;", "NRNSBPRO;", "HHIBOX;"];  
  List<String> _availablePorts = [];
  LocalPlugin localPlugin = LocalPlugin();
  MicrophoneUtil microphoneUtil = MicrophoneUtil();
  final double _sliderValue = 25;
  double startValue = 0;
  final double endValue = 22000;
  int _sampleRate = 44100;
  double displayTimeMs = 10000;


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

  final List<Color> availableColors = {
    ...ChannelColorDefaults.audioChannelColors,
    ...ChannelColorDefaults.serialChannelColors,
    Colors.green,
    Colors.red,
    Colors.blue,
    Colors.orange,
    Colors.purple,
    Colors.yellow,
    Colors.teal,
    Colors.pink,
  }.toList();

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

  late ProcessingUtil processingUtil;

  @override
  void didUpdateWidget(covariant GraphTemplate oldWidget) {
    super.didUpdateWidget(oldWidget);
    _frameDetect = FrameDetect(channelCount: widget.channelCount, minimumBytesToCheck: 50);
    _bitwiseUtil = BitwiseUtil(bitCount: widget.bitsData);
    _channelBytes = widget.channelCount * 2;
  }

  int dummyCount = 0;

  // bool isAudioListen = false;

  Future<void> _startPortCheck() async {
    Timer.periodic(const Duration(seconds: 3), (timer) async {
      int baudRate = context.read<ConstantProvider>().getBaudRate();
      _serialUtil.getAvailablePorts(baudRate, listenToMicrophone);
      allDevices.clear();

      List<String> filteredPorts;
      if (Platform.isMacOS) {
        filteredPorts = _serialUtil.availablePorts.where((port) => port.contains('usbmodem') || port.contains('usbserial')).toList();
      } else {
        filteredPorts = _serialUtil.availablePorts;
      }

      bool isComMatch = areListsEqual(_availablePorts, filteredPorts);

      _availablePorts = filteredPorts;

      context.read<DataStatusProvider>().setMicrophoneDataStatus(_availablePorts.isEmpty);

      if (!isComMatch) {
        // isDeviceConnect = true; 
        // isDeviceSelected = false;

        Provider.of<PortScanProvider>(context, listen: false).setPortScanList(_availablePorts);

        Provider.of<ConstantProvider>(context, listen: false).setBaudRate(baudRate);
        allDevices = context.read<SerialDataProvider>().getAllPortDetail;
        if (isDeviceConnect) {
          await portListOnConnect();
        }
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
    final myDataProvider = Provider.of<SampleRateProvider>(context, listen: false);

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

    // Initialize ProcessingUtil
    processingUtil = createProcessingUtil();
    
    final provider = Provider.of<GraphDataProvider>(context, listen: false);
    
    // Initialize stream and set provider
    _graphStream = _graphStreamController.stream.asBroadcastStream();
    provider.setStreamOfData(_graphStream);
    
    SchedulerBinding.instance.addPostFrameCallback((timeStamp) async {
      setSampleRate();
    });
    if (!kIsWeb) {
      _startPortCheck();
    }

    listenToMicrophone(1, provider);

    filterBaseSettingsModel = FilterSetup(filterConfiguration: FilterConfiguration(cutOffFrequency: 1000, sampleRate: 10000), filterType: FilterType.highPassFilter, channelCount: channelCountBuffer, isFilterOn: false);
    _sampleData = GenerateSampleData.sineWaveUint14(samplingRate: dummySamplingRate, frequencies: [50, 1000], samplesGenerated: _sampleGeneratedCount).buffer.asUint8List();

    Timer.periodic(const Duration(milliseconds: timeMs), (timer) {
      bool dummyDataStatus = context.read<DataStatusProvider>().isSampleDataOn;
      if (dummyDataStatus) {
        _preprocessingBuffer.addBytes(_sampleData);
      }
    });

    localPlugin.spawnHelperIsolate().then(
      (value) {
        localPlugin.postFilterStream?.listen((serialData) {
          bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
          if (!isAudioListen) {
            if (kIsWeb) {
              provider.inputListener(Uint8List(0));
            }
          }
          // _preGraphBuffer.addBytes(event);
        });
        localPlugin.postDisplayStream?.listen((event) {
          bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
          if (isAudioListen) {
            provider.inputListener(event);
          }
        });
      },
    );
    _preprocessingBuffer = BufferHandler(
      chunkReadSize: 2000,
      onDataAvailable: (Uint8List listBytes) async {
        int bitData = context.read<ConstantProvider>().getBitData();

        Uint16List newDataPoints;
        Int16List int16list;
        List<int> newPoints;
        bool dummyDataStatus = context.read<DataStatusProvider>().isSampleDataOn;
        bool isEnableAudio = context.read<DataStatusProvider>().isMicrophoneData;
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
        //   int bitData = Provider.of<ConstantProvider>(context, listen: false).getBitData();
        //   Uint8List transformedData = _bitwiseUtil.convertToValue(listBytes);
        //   newDataPoints = transformedData.buffer.asUint16List();
        //   newPoints = List.filled(newDataPoints.length, 0);

        //   for (int i = 0; i < newPoints.length; i++) {
        //     int a = 0;
        //     int e = newDataPoints[i];
        //     // a = e;

        //     switch (bitData) {
        //       case 14:
        //         a = e - 8192;
        //         // print("value of a: $a, e: $e");
        //         break;

        //       case 10:
        //         a = (e * 30) - 15360; // (value - 512) * 30
        //         break;

        //       default:
        //         break;
        //     }
        //     newPoints[i] = a;
        //   }
        // }

        
        }
        // await localPlugin.filterArrayElements(
        //   array: newPoints,
        //   arrayLength: newPoints.length,
        //   channelIdx: 0,
        // );
      },
    );

    _frameDetect = FrameDetect(channelCount: widget.channelCount, minimumBytesToCheck: 50);
    _bitwiseUtil = BitwiseUtil(bitCount: widget.bitsData);
    _channelBytes = widget.channelCount * 2;



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
      String responseMessage = MessageValueSet.fromUint8ListCommand(message: msg).value;
      print("responseMessage :  $responseMessage");
      String? devices = checkConnectedDevices(responseMessage);

      if (devices == null) {
        return;
      }
      _deviceName.value = devices;
      print("devices :   $devices");
      // if (_deviceName.value != null) {
      //   deviceType = listOfDevices.indexOf(_deviceName.value!);
      //   print("deviceType");
      //   print(deviceType);
      // }

      SetUpFunctionality().setTheDeviceSetting(_deviceName.value).then((value) {
        print("VALUE : $value");
        if (value != null) {
          String tempDevices = value.uniqueName ?? "";
          if (foundDevices != "") {
            if (foundDevices != tempDevices){
              foundDevices = tempDevices;
            } else {
              return;
            }
          } else {
            foundDevices = tempDevices;
          }
          print("foundDevices");
          print(foundDevices);
          // HARDCODE
          if (foundDevices == "MUSCLESS") {
            foundDevices = "HEARTSS";
          }
          

          Provider.of<ConstantProvider>(context, listen: false).setBaudRate(foundDevices == "HHIBOX" ? 500000 : 222222);
          Provider.of<ConstantProvider>(context, listen: false).setChannelCount(int.parse(value.maxNumberOfChannels.toString()));
          Provider.of<ConstantProvider>(context, listen: false).setBitData(int.parse(value.sampleResolution.toString()));
          Provider.of<SampleRateProvider>(context, listen: false).setSampleRate(int.parse(value.maxSampleRate.toString()));

          connectedDevices.add(foundDevices);
          SerialPortDataModel serialData = SerialPortDataModel(portCom: portName, deviceDetect: foundDevices);
          context.read<SerialDataProvider>().setPortOfDevices(serialData);
          print("isDeviceConnect: ");
          print(isDeviceConnect);
          // if (isDeviceConnect) {
          bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
          if (!isAudioListen) {

            SetUpFunctionality().getAllDeviceList().then((value) {
              print("INIT STATE GET ALL DEVICE LIST");
              // Extract the list of boards from the result
              List<Board> allBoards = value.boards ?? [];
              // Filter the boards based on some condition (e.g., matching unique names)
              List<Board> connectedBoards = allBoards.where((board) {
                return connectedDevices.contains(board.uniqueName);
              }).toList();

              // Add the filtered list to the stream
              // List<ComDataWithBoard> listOfBoard = createComDataWithBoardList(connectedBoards, allDevices);
              // print("listOfBoard");
              // print(allBoards);
              // print(listOfBoard);
              // print(connectedBoards);
              for (Board board in connectedBoards) {
                if (board.uniqueName == foundDevices) {
                  GraphTemplate.selectedBoard = board;
                  // HARDCODE
                  deviceType = listOfDevices.indexOf("$foundDevices;") + 1;
                  print("${GraphTemplate.selectedBoard} ${board.uniqueName} --- $foundDevices ::: ${board.uniqueName == foundDevices} $deviceType" );
                  // (processingUtil as ProcessingUtilImpl).dispose();
                  // processingUtil = createProcessingUtil();
                  _sampleRate = int.parse(board.maxSampleRate!);
                  double drawSurfaceWidth = MediaQuery.of(context).size.width;
                  processingUtil.initializeSerial(board, drawSurfaceWidth);
                  context.read<ChannelColorProvider>().setSerialChannelCount(
                      int.parse(board.maxNumberOfChannels!));
                  context.read<ChannelFilterProvider>().setSerialChannelCount(
                      int.parse(board.maxNumberOfChannels!));
                  // createDisplaySerialDataIsolate();
                  // createProcessSerialDataIsolate();
                  Future.delayed(Duration(seconds: 2), (){
                    var info = processingUtil.getInformation();
                    print("info : $info");
                    isDeviceSelected = true;
                  });
                }
              }

              // Print the stream (optional)
            });
          }

        }
      });
      Debugging.printing("Message received from Spikerbox: \n\tbytes : $msg\n\tstring: ${String.fromCharCodes(msg)}");
  //     Message received from Spikerbox: 
	// bytes : [72, 87, 84, 58, 72, 85, 77, 65, 78, 83, 66, 59]
	// string: HWT:HUMANSB;
    });

    _preEscapeSequenceBuffer = BufferHandler(
      chunkReadSize: 32,
      onDataAvailable: (Uint8List dataFromBuffer) {
        // print("message identifier : ${dataFromBuffer}");
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
              _graphStreamController.add(ChannelUtil.dropEveryOtherTwoBytes(dataFromBuffer));
              break;
          }
        }
      },
    );

    final providerScroll = Provider.of<GraphDataProvider>(context, listen: false);
    providerScroll.zoomEvents.listen((scrollDelta) {
      setState(() {
        if (scrollDelta > 0) {
          displayTimeMs *= 1.1;
        } else {
          displayTimeMs *= 0.9;
        }
        displayTimeMs = displayTimeMs.clamp(5.0, 10000.0);
        // get current position
        // get next position
        // get difference in position
        providerScroll.broadcastDisplayTime(displayTimeMs);

        if (GraphTemplate.isPlayerPaused) {
          // int drawSurfaceWidth = MediaQuery.of(context).size.width.toInt();
          double prevStartElementIdx = screenPositionToElementPosition(SoundWaveView.dragDetails!.position.dx, _sampleRate, ProcessingUtil.positionIndex, 
            TimeCalculateWidget.prevDisplayTimeMsLabel *0.001, TimeCalculateWidget.prevWidthOfScale, MediaQuery.of(context).size.width, bufferPos);
          double startElementIdx = screenPositionToElementPosition(SoundWaveView.dragDetails!.position.dx, _sampleRate, ProcessingUtil.positionIndex, 
            TimeCalculateWidget.displayTimeMsLabel *0.001, TimeCalculateWidget.widthOfScale, MediaQuery.of(context).size.width, bufferPos);
          print("DIFFERENCES = $prevStartElementIdx - $startElementIdx = ${prevStartElementIdx - startElementIdx} | ${ProcessingUtil.positionIndex}");
          bufferPaddingLeft = bufferPaddingLeft - (prevStartElementIdx - startElementIdx);
          if (displayTimeMs == 10000) {
            bufferPaddingLeft = 0;
          }
          // if (bufferPaddingLeft < 0) {
          //   bufferPaddingLeft = 0;
          // }
        }else {
          bufferPaddingLeft = 0;
        }

      });
    });
  
    setState(() {
      
    });

  }

  @override
  void dispose() {
    (processingUtil as ProcessingUtilImpl).dispose();
    super.dispose();
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

    int index = listOfDevices.indexWhere((element) => element == getResponse);
    if (index == -1) return null;
    return listOfDevices[index];
  }

  final List<int> _dataBit = [14, 10];
  final List<int> _baudRate = [222222, 230400, 500000];
  final List<int> _channelCount = [1, 2];

  String portName = "";
  bool isDeviceConnect = true;
  bool isDeviceSelected = false;
  bool isSettingEnable = false;
  
  List<ComDataWithBoard>? listOfBoard;
  
  String foundDevices = "";
  
  int deviceType = -1;

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
                      context.read<SoftwareConfigProvider>().settingStatus(false);
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
                        processingUtil: processingUtil,
                        isMicrophoneEnable: (bool isMicrophoneEnable) {
                          context.read<DataStatusProvider>().setMicrophoneDataStatus(isMicrophoneEnable);
                        },
                        onHighPassFilterSetup: (FilterSetup filterSetup) {
                          // Keep this for backward compatibility if needed
                        },
                        onLowPassFilterSetup: (FilterSetup filterSetup) {
                          // Keep this for backward compatibility if needed
                        },
                        onSampleChange: (bool isSampleDataOn) {
                          context.read<DataStatusProvider>().setSampleDataStatus(isSampleDataOn);
                        },
                        startValue: startValue,
                        endValue: endValue,
                        sliderValue: _sliderValue,
                      ),
                      const SizedBox(
                        height: 10,
                      ),
                      NotchPassFilterWidget(sampleRateParam:_sampleRate.toDouble(), onTapNotchFrequency: (notchFilterSettings) async {
                        notchFilterSettings.filterConfiguration.sampleRate = _sampleRate;
                        print("the notch filter setting is ${notchFilterSettings.toJson()}");
                        if (notchFilterSettings.isFilterOn) {
                          if (notchFilterSettings.filterConfiguration.cutOffFrequency == 50) {
                            int temp = await processingUtil.setNotchFilter(50);
                            print("processingUtil.setNotchFilter(50) $temp");
                          } else 
                          if (notchFilterSettings.filterConfiguration.cutOffFrequency == 60) {
                            processingUtil.setNotchFilter(60);
                            print("processingUtil.setNotchFilter(60)");
                          } else {
                            processingUtil.setNotchFilter(-1);
                          }
                        }

                        context.read<DataStatusProvider>().setNotchPassFilterSetting(notchFilterSettings);
                        // localPlugin.initNotchPassFilters(notchFilterSettings);
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
                                      FilterProcessWidget(isMicrophoneEnable: (bool isMicrophoneEnable) {
                                        // _toEnableMicrophone =
                                        //     isMicrophoneEnable;

                                        context.read<DataStatusProvider>().setMicrophoneDataStatus(isMicrophoneEnable);
                                      }, onHighPassFilterSetup: (FilterSetup filterSetup) {
                                        localPlugin.initHighPassFilters(filterSetup);
                                      }, onLowPassFilterSetup: (FilterSetup filterSetup) {
                                        localPlugin.initLowPassFilters(filterSetup);
                                      }, onSampleChange: (bool isSampleDataOn) {
                                        context.read<DataStatusProvider>().setSampleDataStatus(isSampleDataOn);
                                        // _toGenerateDummyData =
                                        //     isSampleDataOn;
                                      }),
                                      _channelColorSettings(),
                                      _channelFilterSettings(),
                                      // DropdownButtonFormField<int>(
                                      //   dropdownColor: SoftwareColors.kDropDownBackGroundColor,
                                      //   style: SoftwareTextStyle().kWtMediumTextStyle,
                                      //   items: _dataBit
                                      //       .map(
                                      //         (e) => DropdownMenuItem(
                                      //           value: e,
                                      //           child: Text(
                                      //             e.toString(),
                                      //           ),
                                      //         ),
                                      //       )
                                      //       .toList(),
                                      //   onChanged: (int? bitDataSelect) {
                                      //     context.read<ConstantProvider>().setBitData(bitDataSelect!);
                                      //   },
                                      //   value: context.read<ConstantProvider>().getBitData(),
                                      // ),
                                      // DropdownButtonFormField(
                                      //   dropdownColor: SoftwareColors.kDropDownBackGroundColor,
                                      //   style: SoftwareTextStyle().kWtMediumTextStyle,
                                      //   items: _baudRate
                                      //       .map(
                                      //         (e) => DropdownMenuItem(
                                      //           value: e,
                                      //           child: Text(
                                      //             e.toString(),
                                      //           ),
                                      //         ),
                                      //       )
                                      //       .toList(),
                                      //   onChanged: (baudRateSelect) {
                                      //     context.read<ConstantProvider>().setBaudRate(baudRateSelect!);
                                      //   },
                                      //   value: context.read<ConstantProvider>().getBaudRate(),
                                      // ),
                                      // DropdownButtonFormField(
                                      //   dropdownColor: SoftwareColors.kDropDownBackGroundColor,
                                      //   style: SoftwareTextStyle().kWtMediumTextStyle,
                                      //   items: _channelCount
                                      //       .map(
                                      //         (e) => DropdownMenuItem(
                                      //           value: e,
                                      //           child: Text(
                                      //             e.toString(),
                                      //           ),
                                      //         ),
                                      //       )
                                      //       .toList(),
                                      //   onChanged: (int? channelCountSelect) {
                                      //     context.read<ConstantProvider>().setChannelCount(channelCountSelect!);
                                      //   },
                                      //   value: context.read<ConstantProvider>().getChannelCount(),
                                      // ),
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Consumer<PortScanProvider>(builder: (context, portList, snapshot) {
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

                                      // // if (!mounted) return;
                                      // // bool dummyDataStatus = context
                                      // //     .read<DataStatusProvider>()
                                      // //     .isSampleDataOn;
                                      // // bool isAudioListen = context
                                      // //     .read<DataStatusProvider>()
                                      // //     .isMicrophoneData;
                                      // // try {
                                      // //   _serialUtil.dataStream?.listen((event) {
                                      // //     if (!dummyDataStatus &&
                                      // //         !isAudioListen) {
                                      // //       _preEscapeSequenceBuffer
                                      // //           .addBytes(event);
                                      // //       if (isDeviceConnect) {
                                      // //         _serialUtil.writeToPort(
                                      // //             bytesMessage: UsbCommand
                                      // //                 .hwTypeInquiry
                                      // //                 .cmdAsBytes(),
                                      // //             address: add);

                                      // //         isDeviceConnect = false;
                                      // //       }
                                      // //       if (_isDataIdentified) {
                                      // //         // Debugging.printing('us: ${stopwatch.elapsedMicroseconds}, length : ${event.length}');
                                      // //         // stopwatch.reset();
                                      // //       } else {
                                      // //         Uint8List? firstFrameData =
                                      // //             _frameDetect.addData(event);

                                      // //         if (firstFrameData != null) {
                                      // //           _preEscapeSequenceBuffer
                                      // //               .addBytes(firstFrameData);
                                      // //           _isDataIdentified = true;
                                      // //         }
                                      // //       }
                                      // //     }
                                      // //   });
                                      // //   portName = add;
                                      // // } catch (e) {
                                      // //   print(
                                      // //       "the error is $e from serial port");
                                      // // }
                                    },
                                    onWrite: (String add) async {
                                      MessageValueSet? selectedCommand = await showCommandPopUp(add);
                                      if (selectedCommand != null) {
                                        _serialUtil.writeToPort(bytesMessage: selectedCommand.cmdAsBytes(), address: add);
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
                            context.read<SoftwareConfigProvider>().settingStatus(true);
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
                              listOfBoard = snapshot.data!;
                              return SizedBox(
                                height: 50,
                                child: ListView.builder(
                                    padding: EdgeInsets.zero,
                                    scrollDirection: Axis.horizontal,
                                    shrinkWrap: true,
                                    itemCount: listOfBoard?.length,
                                    itemBuilder: (context, index) {
                                      return GestureDetector(
                                        onTap: () {
                                          if (listOfBoard != null) {
                                            Provider.of<ConstantProvider>(context, listen: false).setBaudRate(int.parse(listOfBoard![index].connectDevices.maxSampleRate.toString()));
                                            Provider.of<ConstantProvider>(context, listen: false).setChannelCount(int.parse(listOfBoard![index].connectDevices.maxNumberOfChannels.toString()));
                                            Provider.of<ConstantProvider>(context, listen: false).setBitData(int.parse(listOfBoard![index].connectDevices.sampleResolution.toString()));
                                          }
                                        },
                                        child: SpikerBoxButton(onTapButton: () {}, iconData: Icons.usb),
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
                  Provider.of<GraphResumePlayProvider>(context, listen: false).setGraphResumePlay(isPlay);
                  _toPauseGraph = isPlay;
                },
              ),
            ],
          )),
      floatingActionButton: kIsWeb
          ? FloatingActionButton.extended(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(width: 2, color: Colors.grey)),
              backgroundColor: SoftwareColors.kButtonBackGroundColor,
              onPressed: () async {
                try {
                  serialDataSubscription?.cancel();
                  int baudRate = context.read<ConstantProvider>().getBaudRate();
                  print("getAvailablePorts");
                  await _serialUtil.getAvailablePorts(baudRate, listenToMicrophone);
                  _availablePorts = _serialUtil.availablePorts;
                  if (!mounted) return;
                  Provider.of<PortScanProvider>(context, listen: false).setPortScanList(_availablePorts);
                  context.read<DataStatusProvider>().setMicrophoneDataStatus(false);

                  if (!mounted) return;
                  bool dummyDataStatus = context.read<DataStatusProvider>().isSampleDataOn;
                  bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
                  final provider = Provider.of<GraphDataProvider>(context, listen: false);
                  print("_serialUtil.dataStream $isAudioListen $dummyDataStatus | $_isDataIdentified $isDeviceSelected");
                  isDeviceConnect = true;
                  isDeviceSelected = false;
                  _isDataIdentified = false;

                  serialDataSubscription = _serialUtil.dataStream?.listen((event) async {
                    if (!dummyDataStatus && !isAudioListen) {
                      int drawSurfaceWidth = MediaQuery.of(context).size.width.toInt();
                      if (isDeviceConnect) {
                        _serialUtil.writeToPort(bytesMessage: UsbCommand.hwTypeInquiry.cmdAsBytes(), address: _availablePorts.last);
                        isDeviceConnect = false;
                      }
                      if (_isDataIdentified) {
                        if (!GraphTemplate.isPlayerPaused) {
                          processingUtil.processSerialData(event, displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider).then((sampleCount) {
                            totalSampleCount += sampleCount;
                            // print("totalSampleCount: $totalSampleCount");
                            if (totalSampleCount > sampleCountToDisplay) {
                              totalSampleCount = 0;
                              processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider, 0, (displayTimeMs * 0.001 * _sampleRate).floor());
                            }
                          });
                        } else {
                          if (SoundWaveView.dragDetails != null) {
                            int fromSample = (-bufferPaddingLeft).toInt();
                            int toSample = (fromSample + displayTimeMs * 0.001 * _sampleRate).toInt();
                            // processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, fromSample, toSample );
                            processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider, fromSample, toSample);
                          } else {
                          }                          
                        }
                      } else {
                        if (!isDeviceConnect && !isDeviceSelected) {
                          _preEscapeSequenceBuffer.addBytes(event);
                          // print("ENTER:  $event = $isAudioListen $dummyDataStatus | $_isDataIdentified $isDeviceSelected");

                        }
                        if (isDeviceSelected) { // !isDeviceConnect &&
                          _isDataIdentified = true;
                          // STEVE
                          processingUtil.processSerialData(event, displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider).then((sampleCount) {
                            totalSampleCount += sampleCount;
                            if (totalSampleCount > sampleCountToDisplay) {
                              totalSampleCount = 0;
                              processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider, 0, (displayTimeMs * 0.001 * _sampleRate).floor());
                            }
                          });

                        }
                      }
                    }                    
                    /*
                    if (!dummyDataStatus && !isAudioListen) {
                      if (isDeviceConnect) {
                        _serialUtil.writeToPort(bytesMessage: UsbCommand.hwTypeInquiry.cmdAsBytes(), address: _availablePorts.last);
                        isDeviceConnect = false;
                        _preEscapeSequenceBuffer.addBytes(event);
                      } else {
                        int drawSurfaceWidth = MediaQuery.of(context).size.width.toInt();

                        if (_isDataIdentified) {
                          // Debugging.printing('us: ${stopwatch.elapsedMicroseconds}, length : ${event.length}');
                          // stopwatch.reset();
                          // print("_ISDATA IDENTIFIED");
                          if (!isDeviceSelected) {
                            _preEscapeSequenceBuffer.addBytes(event);
                          } else {
                            // print("process SERIAL data");
                            processingUtil.processSerialData(event, displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider);
                          }
                        } else {
                          Uint8List? firstFrameData = _frameDetect.addData(event);

                          if (firstFrameData != null) {
                            _preEscapeSequenceBuffer.addBytes(firstFrameData);
                            processingUtil.processSerialData(firstFrameData, displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider);
                            _isDataIdentified = true;
                          } else {
                            _preEscapeSequenceBuffer.addBytes(event);
                          }
                        }
                      }                      



                      // int drawSurfaceWidth = MediaQuery.of(context).size.width.toInt();
                      // if (_isDataIdentified) {
                      //   // _preEscapeSequenceBuffer.addBytes(Uint8List(0));
                      //   // Debugging.printing('us: ${stopwatch.elapsedMicroseconds}, length : ${event.length}');
                      //   // stopwatch.reset();
                      //   // localPlugin.filterArrayElements(array: array, arrayLength: arrayLength, channelIdx: channelIdx);
                      //   // print("ISDAATA WEB");
                        
                      //   processingUtil.processSerialData(event, displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider);
                      // } else {
                      //   print("isDeviceConnect Web : $isDeviceConnect === $_isDataIdentified");
                      //   if (isDeviceConnect) {
                      //     _serialUtil.writeToPort(bytesMessage: UsbCommand.hwTypeInquiry.cmdAsBytes(), address: _availablePorts.last);
                      //     isDeviceConnect = false;
                      //   }else {
                      //     Uint8List? firstFrameData = _frameDetect.addData(event);

                      //     if (firstFrameData != null) {
                      //       // print("IS DEVICE ALREADY CONNECT AND firstFrameData");
                      //       _preEscapeSequenceBuffer.addBytes(firstFrameData);
                      //       processingUtil.processSerialData(firstFrameData, displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider);
                      //       _isDataIdentified = true;
                      //     }else {
                      //       _preEscapeSequenceBuffer.addBytes(event);
                      //       // print("IS DEVICE ALREADY CONNECT but not firstFrameData");
                      //       // localPlugin.sendSerialData(event);
                      //     }
                      //   }
                      // }
                    }
                    */
                  }, onError: (error) {
                    // if (error is SerialPortError) {
                      print("SERIAL PORT ERROR -- DISCONNECTED");
                      Future.delayed(Duration(milliseconds: 2500), () {
                        _serialUtil.closePort();
                        listenToMicrophone(1, provider);
                      });
                    // }
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
    StreamController<List<ComDataWithBoard>> deviceListStream = StreamController<List<ComDataWithBoard>>();

    // Obtain the stream from the stream controller
    Stream<List<ComDataWithBoard>>? deviceList = deviceListStream.stream.asBroadcastStream();

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
        List<ComDataWithBoard> deviceDataWithCom = createComDataWithBoardList(connectedBoards, allDevices);
        deviceListStream.add(deviceDataWithCom);

        // Print the stream (optional)
      });
    } else {
      return null;
    }

    // Return the broadcast stream
    return deviceList;
  }

  List<ComDataWithBoard> createComDataWithBoardList(List<Board> connectedBoards, List<SerialPortDataModel> allDevices) {
    List<ComDataWithBoard> result = [];

    for (SerialPortDataModel device in allDevices) {
      Board matchingBoard = connectedBoards.firstWhere(
        (board) => board.uniqueName == device.deviceDetect,
        orElse: () => Board(/* Default values or handle the case when no match is found */),
      );

      ComDataWithBoard comDataWithBoard = ComDataWithBoard(
        connectDevices: matchingBoard,
        serialPortData: device,
      );

      result.add(comDataWithBoard);
    }

    return result;
  }

  List<int> serialBuffer = [];
  
  Future<void> portListOnConnect() async {
    DataStatusProvider dataStatus = context.read<DataStatusProvider>();
    List<String> listOfPort = Provider.of<PortScanProvider>(context, listen: false).availablePorts;
    int baudRate = context.read<ConstantProvider>().getBaudRate();
    if (listOfPort.isEmpty) {
      return;
    }
    Stream<Uint8List>? getData = await _serialUtil.openPortToListen(listOfPort.last, baudRate);
    bool dummyDataStatus = dataStatus.isSampleDataOn;
    bool isAudioListen = dataStatus.isMicrophoneData;
    dataStatus.setDeviceDataStatus(true);
    var rng = Random();
    List<int> initialSamples = [];
    int headIdx = 0;
    int headLimit = 4 * 20000;
    if (initialSamples.isEmpty) {
      for (int i = 1; i < 20001; i++) {
        // initialSamples.addAll([255,255,1,1,128,255]);
        initialSamples.addAll([ 191, 20, 64, 115]);
        // initialSamples.addAll([0,10 * i,0,20 * i]);
        // initialSamples.addAll([0,10 * i,0,20 * i]);
        // initialSamples.addAll([255,255,1,1,129,255]);
      }
    }
    Uint8List initialSamplesArr = Uint8List.fromList(initialSamples);

    // Stopwatch stopwatch = Stopwatch();
    final provider = Provider.of<GraphDataProvider>(context, listen: false);
    totalSampleCount = 0;

    serialDataSubscription?.cancel();
    serialDataSubscription = getData?.listen((event) async {
      if (!dummyDataStatus && !isAudioListen) {
        int drawSurfaceWidth = MediaQuery.of(context).size.width.toInt();
        if (isDeviceConnect) {
          _serialUtil.writeToPort(bytesMessage: UsbCommand.hwTypeInquiry.cmdAsBytes(), address: listOfPort.last);
          isDeviceConnect = false;
        }
        if (_isDataIdentified) {
          // print("event");
          // print(event);
          // Uint8List char = initialSamplesArr.sublist(headIdx, (headIdx + 4) );
          // print("char");
          // print(char);
          // processingUtil.processSerialData(char, displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider);
          // (headIdx +=4);
          // if (headIdx >= headLimit) {
          //   isDeviceSelected = false;
          //   _isDataIdentified = false;
          //   headIdx = 0;
          // }

          // STEVE
          // if (event.reduce(max) > 250) {
          //   print("isDeviceConnect: $isDeviceConnect - $isDeviceSelected EVENT: $event");
          // } else {
          if (!GraphTemplate.isPlayerPaused) {
            int sampleCount = await processingUtil.processSerialData(event, displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider);
            totalSampleCount += sampleCount;
            if (totalSampleCount > sampleCountToDisplay) {
              totalSampleCount = 0;
              // await processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider);
              await processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider, 0, (displayTimeMs * 0.001 * _sampleRate).floor());
              provider.inputListener(Uint8List(0));
            }
          } else {
            // await processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider);            
            int fromSample = (-bufferPaddingLeft).toInt();
            int toSample = (fromSample + displayTimeMs * 0.001 * _sampleRate).toInt();
            // processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, fromSample, toSample );
            await processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider, fromSample, toSample);

            provider.inputListener(Uint8List(0));
          }
          // }

          // processSerialSendPort?.send([event, displayTimeMs.toInt(), deviceType, drawSurfaceWidth]);
          // if (totalSampleCount >= 1024) {
          //   totalSampleCount = 0;
          //   provider.inputListener(ProcessingUtil.drawingBuffers);
          //   processSerialDisplaySendPort?.send([displayTimeMs.toInt(), deviceType, drawSurfaceWidth]);
          // }

            // await (compute(processingUtil.processSerialDataIsolate, [event, displayTimeMs.toInt(), deviceType, drawSurfaceWidth, null])).then((sampleCount) {
            //   totalSampleCount += sampleCount;
            //   if (totalSampleCount >= _sampleRate / 10) {
            //     print("display");
            //     (compute(processingUtil.displaySerialDataIsolate, [displayTimeMs.toInt(), deviceType, drawSurfaceWidth, null]) ).then((data) {
            //       provider.inputListener(ProcessingUtil.drawingBuffers);
            //     });
            //   }
            //   // print("sampleCount: $sampleCount");
            // });

          /*
          serialBuffer.addAll(event);
          if (serialBuffer.length >= 1024) {
            print("serialBuffer");
            print(serialBuffer);
            serialBuffer.clear();
            // Uint8List resBuffer = Uint8List.fromList(serialBuffer.sublist(0, 1024));
            // serialBuffer.removeRange(0, 1024);
            // processingUtil.processSerialData(resBuffer, displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider);            
          }
          */
        } else {
          if (!isDeviceConnect && !isDeviceSelected) {
            _preEscapeSequenceBuffer.addBytes(event);
          }
          if (isDeviceSelected) { // !isDeviceConnect &&
            _isDataIdentified = true;
            // STEVE
            if (!GraphTemplate.isPlayerPaused) {
              int sampleCount = await processingUtil.processSerialData(event, displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider);            
              totalSampleCount += sampleCount;
              if (totalSampleCount> sampleCountToDisplay) {
                totalSampleCount = 0;
                await processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider, 0, (displayTimeMs * 0.001 * _sampleRate).floor());
                provider.inputListener(Uint8List(0));
              }
            } else {
              // await processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider);
              int fromSample = (-bufferPaddingLeft).toInt();
              int toSample = (fromSample + displayTimeMs * 0.001 * _sampleRate).toInt();
              // processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, fromSample, toSample );
              await processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider, fromSample, toSample);

              provider.inputListener(Uint8List(0));
            }

            // processSerialSendPort?.send([event, displayTimeMs.toInt(), deviceType, drawSurfaceWidth]);
            // if (totalSampleCount >= 16) {
            //   totalSampleCount = 0;
            //   provider.inputListener(ProcessingUtil.drawingBuffers);
            //   processSerialDisplaySendPort?.send([displayTimeMs.toInt(), deviceType, drawSurfaceWidth]);
            // }
            
            // await (compute(processingUtil.processSerialDataIsolate, [event, displayTimeMs.toInt(), deviceType, drawSurfaceWidth, null])).then((sampleCount) {
            //   totalSampleCount += sampleCount;
            //   // if (totalSampleCount >= _sampleRate / 10) {
            //     print("display");
            //     (compute(processingUtil.displaySerialDataIsolate, [displayTimeMs.toInt(), deviceType, drawSurfaceWidth, null]) ).then((data) {
            //       ProcessingUtil.drawingBuffers = data;

            //       print("ProcessingUtil.drawingBuffers");
            //       print(ProcessingUtil.drawingBuffers);
            //       provider.inputListener(ProcessingUtil.drawingBuffers);
            //     });
            //   // }
            //   print("sampleCount: $sampleCount");
            // });
            /*
            serialBuffer.addAll(event);
            if (serialBuffer.length >= 1024) {
              Uint8List resBuffer = Uint8List.fromList(serialBuffer.sublist(0, 1024));
              serialBuffer.removeRange(0, 1024);
              processingUtil.processSerialData(resBuffer, displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider);            
            }
            */

            /*
            Uint8List? firstFrameData = _frameDetect.addData(event);

            if (firstFrameData != null) {
              _isDataIdentified = true;
              // print("firstFrameData.length");
              // print(firstFrameData.length);
              processingUtil.processSerialData(firstFrameData, displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider);            
            } else {
              // processingUtil.processSerialData(event, displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider);            
            }
            */
          }
        }

        // print(
        //     "the time taken is ${stopwatch.elapsedMilliseconds}and the length ${event.length}");
        // stopwatch.reset();
        // if (isDeviceConnect) {
        //   print("Is Device Connect");
        //   _serialUtil.writeToPort(bytesMessage: UsbCommand.hwTypeInquiry.cmdAsBytes(), address: listOfPort.last);
        //   isDeviceConnect = false;
        //   _preEscapeSequenceBuffer.addBytes(event);
        // } else {
        //   int drawSurfaceWidth = MediaQuery.of(context).size.width.toInt();

        //   if (_isDataIdentified) {
        //     // Debugging.printing('us: ${stopwatch.elapsedMicroseconds}, length : ${event.length}');
        //     // stopwatch.reset();
        //     // print("_ISDATA IDENTIFIED");
        //     if (!isDeviceSelected) {
        //       print("! Is Device Selected");
        //       _preEscapeSequenceBuffer.addBytes(event);
        //     } else {
        //       // print("process SERIAL data: $deviceType");
        //       processingUtil.processSerialData(event, displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider);
        //       // _preEscapeSequenceBuffer.addBytes(event);

        //     }
        //   } else {
        //     Uint8List? firstFrameData = _frameDetect.addData(event);

        //     if (firstFrameData != null) {
        //       print("First Frame Data");
        //       _preEscapeSequenceBuffer.addBytes(firstFrameData);
        //       _isDataIdentified = true;
        //     } else {
        //       print("Not First Frame Data");
        //       _preEscapeSequenceBuffer.addBytes(event);
        //     }
        //   }
        // }
      }
      // stopwatch.start();
      // if (!dummyDataStatus && !isAudioListen) {
      //   // print("1050 - GET DATA");
        
      //   int drawSurfaceWidth = MediaQuery.of(context).size.width.toInt();
      //   // stopwatch.reset();

      //   if (_isDataIdentified) {
      //     // _preEscapeSequenceBuffer.addBytes(Uint8List(0));
      //     // Debugging.printing('us: ${stopwatch.elapsedMicroseconds}, length : ${event.length}');
      //     // stopwatch.reset();
      //     // localPlugin.filterArrayElements(array: array, arrayLength: arrayLength, channelIdx: channelIdx);
      //     // print(displayTimeMs);
      //     if (!isDeviceSelected) {
      //       _preEscapeSequenceBuffer.addBytes(event);
      //     } else {
      //       localPlugin.processSerialData(event, displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider);
      //     }
      //   } else {
      //     if (isDeviceConnect) {
      //       _preEscapeSequenceBuffer.addBytes(event);            
      //       _serialUtil.writeToPort(bytesMessage: UsbCommand.hwTypeInquiry.cmdAsBytes(), address: _availablePorts.last);
      //       isDeviceConnect = false;
      //     }else {
      //       Uint8List? firstFrameData = _frameDetect.addData(event);

      //       if (firstFrameData != null) {
      //         // print("IS DEVICE ALREADY CONNECT AND firstFrameData");
      //         _preEscapeSequenceBuffer.addBytes(firstFrameData);
      //         localPlugin.processSerialData(firstFrameData, displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider);
      //         _isDataIdentified = true;
      //       }else {
      //         _preEscapeSequenceBuffer.addBytes(event);
      //         // print("IS DEVICE ALREADY CONNECT but not firstFrameData");
      //         // localPlugin.sendSerialData(event);
      //       }
      //     }
      //   }
      // }

      // if (!dummyDataStatus && !isAudioListen) {
      //   _preEscapeSequenceBuffer.addBytes(event);
      //   // print(
      //   //     "the time taken is ${stopwatch.elapsedMilliseconds}and the length ${event.length}");
      //   stopwatch.reset();
      //   if (isDeviceConnect) {
      //     _serialUtil.writeToPort(bytesMessage: UsbCommand.hwTypeInquiry.cmdAsBytes(), address: listOfPort.last);

      //     isDeviceConnect = false;
      //   }
      //   if (_isDataIdentified) {
      //     // Debugging.printing('us: ${stopwatch.elapsedMicroseconds}, length : ${event.length}');
      //     // stopwatch.reset();
      //   } else {
      //     Uint8List? firstFrameData = _frameDetect.addData(event);

      //     if (firstFrameData != null) {
      //       _preEscapeSequenceBuffer.addBytes(firstFrameData);
      //       _isDataIdentified = true;
      //     }
      //   }
      // }
    }, onError: (error) {
      // if (error is SerialPortError) {
        print("SERIAL PORT ERROR -- DISCONNECTED");
        listenToMicrophone(1, provider);
        // processingUtil.init();
        // processingUtil.initializeMicrophone(1, _sampleRate, MediaQuery.of(context).size.width);
      // }
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
                  selectedValue = dropDownChanges as MessageValueSet; // Update selected value
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
  
  StreamSubscription<Uint8List>? microphoneSubscription;
  StreamSubscription<Uint8List>? serialDataSubscription;
  
  SendPort? processSerialSendPort;
  ReceivePort? processSerialReceivePort;
  SendPort? processSerialDisplaySendPort;
  ReceivePort? processSerialDisplayReceivePort;
 
  int totalSampleCount = 0;
  int sampleCountToDisplay = 8;

  double bufferPaddingLeft = 0;
  
  Board? selectedBoard;
  
  void listenToMicrophone(channelCount, provider) {
    isDeviceConnect = true;
    isDeviceSelected = false;
    _isDataIdentified = false;
    foundDevices = "";
    Future.delayed(const Duration(seconds: 2)).then((value) async {
      print("_messageIdentifier.messageState");
      print(_messageIdentifier.messageState);
      // Initialize both utils
      try{
        microphoneUtil.micStream.removeListener(micListener);
        microphoneUtil.micStream = ValueNotifier(Uint8List(0));
        context.read<DataStatusProvider>().setMicrophoneDataStatus(true);
      }catch(err){
        print("er remove listener");
        print(err);
      }

      await Future.wait([
        microphoneUtil.init()
      ]);

      await processingUtil.init();
      //init microphone stream  
      if (kIsWeb) {
        print("WEB SAMPLE RATE : ${microphoneUtil.sampleRate}");
        _sampleRate = microphoneUtil.sampleRate.toInt();
      } else {
        double? tempSampleRate = await MicStream.sampleRate;
        if (tempSampleRate != null) {
          _sampleRate = tempSampleRate.toInt();
        }
      }

      int NUMBER_OF_SEGMENTS = 10;
      int SEGMENT_SIZE = _sampleRate;
      double SIZE = (NUMBER_OF_SEGMENTS * SEGMENT_SIZE).toDouble();
      final SIZE_LOGS2 = 10;

      double size = SIZE;
      int i = 0;
      for (; i < SIZE_LOGS2; i++) {
        envelopeSizes.add(size.toInt());
        size /= 2;
      }
      print("listenToMicrophone2");

      double drawSurfaceWidth = MediaQuery.of(context).size.width;
      await processingUtil.initializeMicrophone(channelCount, _sampleRate, drawSurfaceWidth);
      context.read<ChannelColorProvider>().setAudioChannelCount(channelCount);
      context.read<ChannelFilterProvider>().setAudioChannelCount(channelCount);

      // Set band filter
      await processingUtil.setBandFilter(-1, -1);

      // // // Set notch filter
      // await processingUtil.setNotchFilter(50);
      // print("isAudioListen");
      // print(microphoneUtil.micStream);
      // microphoneSubscription?.cancel();
      // int drawIdx = 0;
      // microphoneSubscription = 
      print("listenToMicrophone5");
      microphoneUtil.micStream.addListener(micListener);    
      isDeviceConnect = true;
      isDeviceSelected = false;

    });
  }

  void micListener(){
    // print("miCLISTENER DATA");
    int channelCount = 1;
    final provider = Provider.of<GraphDataProvider>(context, listen: false);
    bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
    // print("isAUDIO LISTEN: $isAudioListen");
    if (isAudioListen) {
      //_preprocessingBuffer.addBytes(event);
      // List<Int16List> processedData = 
      if (!GraphTemplate.isPlayerPaused) {
        // print("microphoneUtil.micStream.value");
        // print(microphoneUtil.micStream.value);
        processingUtil.processMicrophoneData(microphoneUtil.micStream.value);
      }
      // _preGraphBuffer.addBytes(event);
      
      // if (drawIdx == 3) {
      int drawSurfaceWidth = MediaQuery.of(context).size.width.toInt();
      if (!GraphTemplate.isPlayerPaused) {
        processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, 0, (displayTimeMs*0.001 * microphoneUtil.sampleRate).floor() );
      } else {
        double startElementIdx = 0.0;

        // if (ProcessingUtil.positionIndex > 0) {
          if (SoundWaveView.dragDetails != null) {
            // int level = calculateLevel(displayTimeMs, _sampleRate.toDouble(), drawSurfaceWidth.toDouble(), arrCounts, 0);
            // double divider = ;
            // print("bufferPaddingLeft : $bufferPaddingLeft");
            // int fromSample = (ProcessingUtil.positionIndex - displayTimeMs * 0.001 * _sampleRate - bufferPaddingLeft).toInt();
            int fromSample = (-bufferPaddingLeft).toInt();
            int toSample = (fromSample + displayTimeMs * 0.001 * _sampleRate).toInt();
            // int toSample = (displayTimeMs * 0.001 * _sampleRate).toInt() ;
            // print("fromSample - toSample : $fromSample _ $toSample  ${bufferPaddingLeft} ${displayTimeMs * 0.001 * _sampleRate} ${bufferPos[1]}");
            processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, fromSample, toSample );
            // print("level: $level @@ ${ProcessingUtil.positionIndex} | ${TimeCalculateWidget.prevDisplayTimeMsLabel} - ${TimeCalculateWidget.displayTimeMsLabel} | $prevStartElementIdx $startElementIdx ${prevStartElementIdx - startElementIdx}");
            // print("level: $level @@ ${ProcessingUtil.positionIndex} | ${TimeCalculateWidget.prevWidthOfScale} - ${TimeCalculateWidget.widthOfScale} | $prevStartElementIdx $startElementIdx ${prevStartElementIdx - startElementIdx}");
            // print("bufferPos[1].toInt() - bufferPaddingLeft.toInt(): ${bufferPos[1].toInt()} - ${bufferPaddingLeft.toInt()} == ${bufferPos[1].toInt() - bufferPaddingLeft.toInt()}");

          } else {
            // processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, 0, 10 * _sampleRate );
          }
        // } else {
        //   // List<double> pos = [0, 10.0 * _sampleRate];
        //   // processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, bufferPos[0].floor(), bufferPos[1].floor() );
        // }
      }
      //   drawIdx = 0;
      // }
      // drawIdx++;
    }
  }

  Future<void> createProcessSerialDataIsolate() async {
    processSerialReceivePort = ReceivePort();
    Isolate isolate = await Isolate.spawn(processingUtil.processSerialDataIsolate, processSerialReceivePort?.sendPort);

    Completer<SendPort> isolateSendPortCompleter = Completer<SendPort>();
    processSerialReceivePort?.listen((message) {
      if (message is SendPort) {
        isolateSendPortCompleter.complete(message);
      } else if (message is int) {
        if (message == -1) {
          processSerialReceivePort?.close();
          isolate.kill(priority: Isolate.immediate);
        } else {
          totalSampleCount++;
          // totalSampleCount %= 1024;
          // print("totalSampleCount :  $message");
        }
        // return message; // This return won't work directly in the listener
      } else {
        ProcessingUtil.drawingBuffers = message;
      }
    });
    processSerialSendPort = await isolateSendPortCompleter.future;

    return Future.value(null);
  }

  Future<void> createDisplaySerialDataIsolate() async {
    processSerialDisplayReceivePort = ReceivePort();
    Isolate isolate = await Isolate.spawn(processingUtil.processDisplaySerialDataIsolate, processSerialDisplayReceivePort?.sendPort);

    Completer<SendPort> isolateSendPortCompleter = Completer<SendPort>();
    processSerialDisplayReceivePort?.listen((message) {
      if (message is SendPort) {
        isolateSendPortCompleter.complete(message);
      } else if (message is int) {
        if (message == -1) {
          processSerialDisplayReceivePort?.close();
          isolate.kill(priority: Isolate.immediate);
        } else {
          // totalSampleCount %= 1024;
          // print("totalSampleCount :  $message");
        }
        // return message; // This return won't work directly in the listener
      } else {
        ProcessingUtil.drawingBuffers = message;
      }
    });
    processSerialDisplaySendPort = await isolateSendPortCompleter.future;

    return Future.value(null);
  }

  Widget _buildChannelColorDropdowns(
      ChannelColorProvider provider, bool isAudio) {
    final colors = isAudio ? provider.audioColors : provider.serialColors;
    String title = isAudio ? 'Audio Channel Colors' : 'Serial Channel Colors';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: SoftwareTextStyle().kWtMediumTextStyle),
        ...List.generate(colors.length, (idx) {
          return Row(
            children: [
              Text('Channel ${idx + 1}',
                  style: SoftwareTextStyle().kWtMediumTextStyle),
              const SizedBox(width: 8),
              DropdownButton<Color>(
                value: colors[idx],
                dropdownColor: SoftwareColors.kDropDownBackGroundColor,
                items: availableColors
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Container(width: 20, height: 20, color: c),
                        ))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    if (isAudio) {
                      provider.setAudioColor(idx, val);
                    } else {
                      provider.setSerialColor(idx, val);
                    }
                  }
                },
              ),
            ],
          );
        })
      ],
    );
  }

  Widget _buildChannelFilterCheckboxes(
      ChannelFilterProvider provider, bool isAudio) {
    final filters = isAudio ? provider.audioFilters : provider.serialFilters;
    String title = isAudio ? 'Audio Filters' : 'Serial Filters';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: SoftwareTextStyle().kWtMediumTextStyle),
        ...List.generate(filters.length, (idx) {
          return Row(
            children: [
              Text('Channel ${idx + 1}',
                  style: SoftwareTextStyle().kWtMediumTextStyle),
              const SizedBox(width: 8),
              Checkbox(
                value: filters[idx],
                onChanged: (val) async {
                  if (val == null) return;
                  if (isAudio) {
                    provider.setAudioFilter(idx, val);
                  } else {
                    provider.setSerialFilter(idx, val);
                  }
                  await processingUtil.setChannelFilterEnabled(idx, val);
                },
              ),
            ],
          );
        })
      ],
    );
  }

  Widget _channelColorSettings() {
    return Consumer2<ChannelColorProvider, DataStatusProvider>(
        builder: (context, prov, dataStatus, _) {
      bool isAudioListen = dataStatus.isMicrophoneData;
      if (isAudioListen && prov.audioColors.isNotEmpty) {
        return _buildChannelColorDropdowns(prov, true);
      } else if (!isAudioListen && prov.serialColors.isNotEmpty) {
        return _buildChannelColorDropdowns(prov, false);
      } else {
        return const SizedBox.shrink();
      }
    });
  }

  Widget _channelFilterSettings() {
    return Consumer2<ChannelFilterProvider, DataStatusProvider>(
        builder: (context, prov, dataStatus, _) {
      bool isAudioListen = dataStatus.isMicrophoneData;
      if (isAudioListen && prov.audioFilters.isNotEmpty) {
        return _buildChannelFilterCheckboxes(prov, true);
      } else if (!isAudioListen && prov.serialFilters.isNotEmpty) {
        return _buildChannelFilterCheckboxes(prov, false);
      } else {
        return const SizedBox.shrink();
      }
    });
  }

}

class NotchPassFilterWidget extends StatefulWidget {
  const NotchPassFilterWidget({
    super.key,
    required this.onTapNotchFrequency,
    required this.sampleRateParam,
  });

  final double sampleRateParam;
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

    _notchPassFilterSettings = FilterSetup(filterConfiguration: FilterConfiguration(cutOffFrequency: 50, sampleRate: widget.sampleRateParam.toInt()), filterType: FilterType.notchFilter, channelCount: channelCountBuffer, isFilterOn: false);
  }


  @override
  Widget build(BuildContext context) {
    return Consumer2<SampleRateProvider, DataStatusProvider>(builder: (context, sampleRate, dataStatus, snapshot) {
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
                  _notchPassFilterSettings = _notchPassFilterSettings.copyWith(filterType: FilterType.notchFilter, isFilterOn: value, filterConfiguration: FilterConfiguration(cutOffFrequency: 50, sampleRate: sampleRate.sampleRate));
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
                  print("value");
                  print(value);

                  if (isNotch50) {
                    dataStatus.set50HertzStatus(false);
                    isNotch60 = value!;
                  } else {
                    isNotch60 = value!;
                  }
                  dataStatus.set60HertzStatus(value);
                  _notchPassFilterSettings = _notchPassFilterSettings.copyWith(filterType: FilterType.notchFilter, isFilterOn: value, filterConfiguration: FilterConfiguration(cutOffFrequency: 60, sampleRate: sampleRate.sampleRate));
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
  WhiteColorCheckBox({required this.valueStatus, super.key, required this.onChanged});

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
            decoration: BoxDecoration(border: Border.all(width: 1, color: Colors.white)),
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
  const _AdaptiveArea({required this.child1, required this.child3, required this.child2});

  final Widget child1;
  final Widget child2;
  final Widget child3;

  @override
  State<_AdaptiveArea> createState() => _AdaptiveAreaState();
}

class _AdaptiveAreaState extends State<_AdaptiveArea> {
  @override
  Widget build(BuildContext context) {
    return Consumer<SoftwareConfigProvider>(builder: (context, softwareSetting, snapshot) {
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
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
  const _PortsArea({required this.deviceName, required this.availablePorts, required this.onReceive, required this.onWrite});

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
                  child: Text(address, style: SoftwareTextStyle().kWtMediumTextStyle),
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
  final TextEditingController _lowSampleRateController = TextEditingController();
  final TextEditingController _lowCutOffController = TextEditingController();
  final TextEditingController _highSampleRateController = TextEditingController();
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
    return Consumer<DataStatusProvider>(builder: (context, dataStatus, snapshot) {
      return Column(
        children: [
          // Row(
          //   children: [
          //     WhiteColorCheckBox(
          //       valueStatus: dataStatus.isSampleDataOn,
          //       onChanged: (value) {
          //         setState(() {
          //           _isSampleDataOn = value ?? false;
          //           if (_isSampleDataOn && _isMicrophoneEnable) {
          //             _isMicrophoneEnable = false;
          //             widget.isMicrophoneEnable(_isMicrophoneEnable);
          //           }
          //         });
          //         print("dummySamplingRate : $dummySamplingRate");
          //         Provider.of<SampleRateProvider>(context, listen: false).setSampleRate(dummySamplingRate);
          //         widget.onSampleChange(_isSampleDataOn);
          //       },
          //     ),
          //     Text(
          //       "Sample Data ",
          //       style: SoftwareTextStyle().kWtMediumTextStyle,
          //     )
          //   ],
          // ),
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
