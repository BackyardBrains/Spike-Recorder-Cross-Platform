import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:another_xlider/models/handler.dart';
import 'package:another_xlider/models/tooltip/tooltip.dart';
import 'package:another_xlider/models/trackbar.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_soloud/flutter_soloud.dart' as SoLoud;

import 'package:mic_stream/mic_stream.dart';
// import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:native_add/model/model.dart';
import 'package:nwbfile_plugin/nwbfile_plugin.dart';
import 'package:provider/provider.dart';
import 'package:spikerbox_architecture/constant/const_export.dart';
import 'package:spikerbox_architecture/functionality/debouncer.dart';
import 'package:spikerbox_architecture/functionality/utils.dart';
import 'package:spikerbox_architecture/message_identifier.dart';
import 'package:spikerbox_architecture/models/models.dart';
import 'package:spikerbox_architecture/models/nwbfile_utils/nwbfile_utils.dart';
import 'package:spikerbox_architecture/models/processing_utils/processing_util.dart';
import 'package:spikerbox_architecture/provider/fft_status_provider.dart';
import 'package:spikerbox_architecture/provider/threshold_status_provider.dart';
import 'package:spikerbox_architecture/screen/setting_page.dart';
import 'package:spikerbox_architecture/screen/spiker_box_ui.dart';
import 'package:window_manager/window_manager.dart';
import '../provider/provider_export.dart';
import '../widget/widget_export.dart';
import 'graph_page_widget/sound_wave_view.dart';
import 'package:spikerbox_architecture/models/microphone_stream/microphone_stream_check.dart';

import 'package:another_xlider/another_xlider.dart';


class GraphTemplate extends StatefulWidget {
  static int isLoadingFile = 0;

  static bool isPlayerPaused = false;
  static Board? selectedBoard;
  static ProcessingUtil? processingUtil;
  static NWBFileUtil? nwbFileUtil;
  GraphTemplate({super.key, required this.bitsData, required this.channelCount, required this.baudRate});

  final int bitsData;
  int channelCount = 1;
  final int baudRate;
  @override
  State<GraphTemplate> createState() => _GraphTemplateState();
}

class _GraphTemplateState extends State<GraphTemplate> with WindowListener {
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
      if (isOpeningFile) {
        return;
      }
      // print("SET MICROPHONE DATA STATUS: ${_availablePorts.isEmpty}");
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


    scrubNotifier.addListener(() async {
      List<int> timeScrub = scrubNotifier.value;
      // nwbfile_seek_electrical_series(outSamples, outSampleCounts, outConfig, startTimeStamp, endTimeStamp, selectedChannel, channelCount)
      Int16List arrSamples = Int16List(1);
      loadedMaxSamples = loadedConfig[5];
      int sampleRateConfig = loadedConfig[0].round();

      double arrSamplesLength = ProcessingUtil.MAX_DISPLAY_SECONDS * sampleRateConfig;
      // double arrSamplesLength = maxSamples.toDouble();
      arrSamples = Int16List(arrSamplesLength.floor() * widget.channelCount);
      Int32List arrSampleCount = Int32List(widget.channelCount);

      double percentage = timeScrub[0] / timeScrub[1];
      // double percentage = 0.1;
      // double startSeekSample = (arrSamplesLength * percentage);
      double startSeekSample = loadedMaxSamples * percentage;
      // double endSeekSample = arrSamplesLength; // (arrSamplesLength - startSeekSample).floor()
      double endSeekSample = min(startSeekSample + arrSamplesLength, loadedMaxSamples.toDouble()); // (arrSamplesLength - startSeekSample).floor()
      
      // print("START SEEK SAMPLE: $startSeekSample | END SEEK SAMPLE: $endSeekSample | arrSamplesLength: $arrSamplesLength | loadedMaxSamples: $loadedMaxSamples");
      if (startSeekSample + arrSamplesLength > loadedMaxSamples) {
        return;
      } else {
      }
      startSeekSampleIdx = startSeekSample.floor();
      endSeekSampleIdx = endSeekSample.floor();
      // print("START SEEK SAMPLE IDX: $startSeekSampleIdx $endSeekSampleIdx");


      await GraphTemplate.nwbFileUtil?.seekElectricalSeries(arrSamples, arrSampleCount, loadedConfig, (startSeekSample).floor(), endSeekSample.floor(), 0, widget.channelCount - 1);
      print("Percentage: $percentage @@@ Config: $loadedConfig ||| scrubNotifier: ${timeScrub} ${(arrSamplesLength * percentage).floor()}, ${(arrSamplesLength - startSeekSample).floor()}");
      
      int combinedIdx = 0;
      int totalChannelCount = loadedConfig[1];
      loadedArrSamples.clear();
      loadedArrChannelCount = (Int32List(widget.channelCount));
      for (int i = 0; i < widget.channelCount; i++) {
        // double initialSampleCount = arrSampleCount[i].floor() / totalChannelCount;
        double initialSampleCount = arrSampleCount[i].toDouble();
        loadedArrSamples.add(Int16List(initialSampleCount.floor()));
        loadedArrSamples[i].setAll(0, arrSamples.sublist(combinedIdx, combinedIdx + initialSampleCount.floor()));
        // loadedArrChannelCount.fillRange(0, totalChannelCount, initialSampleCount.floor());
        loadedArrChannelCount[i] = initialSampleCount.floor();
        combinedIdx += initialSampleCount.floor();
      }
      loadedConfig[7] = MediaQuery.of(context).size.width.toInt();
      processingUtil.initWithConfig(loadedConfig);
      
      GraphTemplate.isLoadingFile = 1;
      GraphTemplate.isPlayerPaused = true;

      Future.delayed(Duration(milliseconds: 100), () async{
        context.read<GraphDataProvider>().addListener(() {
          print("GraphDataProvider LISTENER");
          if (context.read<GraphDataProvider>().isRewind) {
            context.read<GraphDataProvider>().resetGraphBuffer();
            // startOpeningFile();
          } 
        });
      });

    });
    context.read<ThresholdStatusProvider>().addListener(() {
      bool isThresholding = context.read<ThresholdStatusProvider>().isThresholding;
      if (isThresholding) {
        int selectedThresholdChannelIdx = context.read<ThresholdStatusProvider>().selectedThresholdChannel;
        int thresholdValue = context.read<ThresholdStatusProvider>().selectedThresholdParam[selectedThresholdChannelIdx];
        processingUtil.setThreshold(thresholdValue.toDouble());
      }
    });

    // Initialize ProcessingUtil
    processingUtil = createProcessingUtil();
    GraphTemplate.processingUtil = processingUtil;
    GraphTemplate.nwbFileUtil = createNwbFileUtil();

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
        }
      }
      _preprocessingBuffer.addBytes(Uint8List.fromList(frameCheckedData));
    }, onDeviceMessage: (Uint8List msg) async {
      String rawMessage = String.fromCharCodes(msg);
      // if (rawMessage.indexOf("EVNT") > -1) {
      //   String responseMessage = MessageValueSet.fromUint8ListCommand(message: msg).value;
      //   responseMessage = responseMessage.replaceAll(";", "");
      //   int eventIndex = 
      //   return;
      // }
      String responseMessage = MessageValueSet.fromUint8ListCommand(message: msg).value;
      print("responseMessage :  $responseMessage - raw: $rawMessage");
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
          widget.channelCount = int.parse(value.maxNumberOfChannels.toString());
          // print("widget.channelCount: $widget.channelCount");
          
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
                  ProcessingUtil.initializeDevice.value = 1;
                  
                  deviceChannelCount = int.parse(board.maxNumberOfChannels!);
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
          // print("DIFFERENCES = $prevStartElementIdx - $startElementIdx = ${prevStartElementIdx - startElementIdx} | ${ProcessingUtil.positionIndex}");
          // print("LABELS: ${DraggableGraph.eventMarkersPosition} ${DraggableGraph.eventMarkersLabels} ||| ${ProcessingUtil.eventLabels.sublist(0, ProcessingUtil.currentEventMarkers)} - Sublist: ${ProcessingUtil.eventPosition.sublist(0, ProcessingUtil.currentEventMarkers)}");

          bufferPaddingLeft = bufferPaddingLeft - (prevStartElementIdx - startElementIdx);
          if (displayTimeMs == 10000) {
            bufferPaddingLeft = 0;
          }
          // if (bufferPaddingLeft < 0) {
          //   bufferPaddingLeft = 0;
          // }
        }else {
          print("LABELS: ${DraggableGraph.eventMarkersPosition} ${DraggableGraph.eventMarkersLabels} ||| ${ProcessingUtil.eventLabels.sublist(0, ProcessingUtil.currentEventMarkers)} - Sublist: ${ProcessingUtil.eventPosition.sublist(0, ProcessingUtil.currentEventMarkers)}");
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
    GraphTemplate.processingUtil = null;
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

  int deviceChannelCount = 1;

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
          notifier: scrubNotifier,
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
          child2: Positioned(
            left: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
              child: Column(
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
                            onTapButton: () {
                              isThresholdingButton = !isThresholdingButton;
                              if (isThresholdingButton) {
                                processingUtil.initThreshold(deviceChannelCount, _sampleRate, MediaQuery.of(context).size.width);
                                print("initThreshold : ${_sampleRate}, $deviceChannelCount ===");
                                processingUtil.setAveragedSampleCount(1);
                                processingUtil.setThreshold(525);
                                processingUtil.setIsThresholding(true);
                              } else {
                                processingUtil.setIsThresholding(false);
                              }
              
                              context.read<ThresholdStatusProvider>().setThresholdStatus(isThresholdingButton);
                              context.read<ThresholdStatusProvider>().setThresholdChannel(0);
              
                              setState((){});
                            },
                            iconColor: isThresholdingButton? Colors.yellow : Colors.black,
                            iconData: Icons.graphic_eq_outlined,
                          ),
                          const SizedBox(
                            width: 20,
                          ),
                          if (isThresholdingButton) ... {
              
                            Center(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton2(
                                  customButton: generateSpikerBoxDecorate(
                                    eventThresholdTriggeredType == "Signal" ? Icon(Icons.stacked_line_chart_outlined) : Center(child: Text(eventThresholdTriggeredType.substring(0,2),))
                                  ),
                                  items: listMenuLabels.map( (item) => DropdownMenuItem<String>(
                                      value:item,
                                      child: Text(item),
                                    )).toList(),
                                  onChanged: (value) {
                                    print("TRIGGER TYPE : $value");
                                    eventThresholdTriggeredType = value!;
                                    int triggerType = listMenuOptions.indexOf(eventThresholdTriggeredType);
                                    processingUtil.setThresholdTriggerType(triggerType);
                                    context.read<ThresholdStatusProvider>().selectedThresholdTriggerType = listMenuOptions.indexOf(eventThresholdTriggeredType);
                                    setState(() {
                                      
                                    });
                                  },
                                  dropdownStyleData: DropdownStyleData(
                                    width: 140,
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      color: Colors.grey.shade100,
                                    ),
                                    offset: const Offset(0, 0),
                                  ),
                                ),
                              ),          
              
                              // child: SpikerBoxButton(
                              //   onTapButton: (){
                              //     isChoosingThresholdType = true;
                              //   }, iconData: Icons.stacked_line_chart_rounded),
                            ),
                            SizedBox(
                              width: 20,
                            ),
                            Container(
                              margin: EdgeInsets.fromLTRB(0, 10, 0, 0),
                              width:200,
                              height:30,
                              child: FlutterSlider(
                                onDragging: (handlerIndex, lowerValue, upperValue) {
                                  print("handlerIndex:  $handlerIndex $lowerValue - $upperValue");
                                  if (handlerIndex == 1) {
                                    thresholdSliderValue = lowerValue.floor();
                                    processingUtil.setAveragedSampleCount(lowerValue.floor());
                                    setState(() {
                                    });
                                  }
                                },
                                onDragCompleted: (handlerIndex, lowerValue, upperValue) {
                                },
                                tooltip: FlutterSliderTooltip(
                                  disabled: true,
                                ),
                                min: 1,
                                max: 50,
                                handler: FlutterSliderHandler(
                                  child: Material(
                                    type: MaterialType.canvas,
                                    color: Colors.grey.shade500,
                                    elevation: 3,
                                    child: Container(
                                        padding: EdgeInsets.all(5),
                                        // child: Icon(Icons.adjust, size: 25,)
                                      ),
                                  ),                                                          
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(0),
                                    color: Colors.grey,
                                    border: Border.all(width: 3, color: Colors.white),
                                  )
                                ),
                                trackBar: FlutterSliderTrackBar(
                                  inactiveTrackBarHeight: 70,
                                  activeTrackBarHeight: 70,
                                  inactiveTrackBar: BoxDecoration(
                                    borderRadius: BorderRadius.circular(0),
                                    color: Colors.grey,
                                    border: Border.all(width: 3, color: Colors.black45),
                                  ),
                                  activeTrackBar: BoxDecoration(
                                    borderRadius: BorderRadius.circular(0),
                                    color: Colors.grey.withOpacity(0.5)
                                  ),
                                ), values: [thresholdSliderValue.floorToDouble()],
                              )
                            ),
                            Container(
                              margin: EdgeInsets.only(top: 15, left:10),
                              height: 30,
                              child: Text(thresholdSliderValue.toString(), style:TextStyle(color: Colors.white)),
                            ),
                            
                            
                            // Container(
                            //   width:50,
                            //   height:30,
                            //   child: TextField(
                            //     controller: thresholdValueController,
                            //   )
                            // )
                          },
                          
                          if (!isThresholdingButton) ... {
                            SpikerBoxButton(
                              onTapButton: () {
                                isFftButton = !isFftButton;
                                if (isFftButton) {
                                  context.read<FftStatusProvider>().setFftVisibility(true);
                                } else {
                                  context.read<FftStatusProvider>().setFftVisibility(false);
                                }
              
                                setState((){});
                              },
                              iconColor: isFftButton? Colors.yellow : Colors.black,
                              iconData: Icons.abc,
                            ),
                          },
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
                                              print("DISCONNECT USB2");
                                              // Future.delayed(Duration(milliseconds: 1500), () {
                                              //   _serialUtil.closePort();
                                              //   final provider = Provider.of<GraphDataProvider>(context, listen: false);
                                              //   listenToMicrophone(1, provider);
                                              // });
              
                                            },
                                            child: SpikerBoxButton(onTapButton: () {
                                              print("DISCONNECT USB");
                                              _serialUtil.closePort();
                                              listenToMicrophone(1, null);
                                              Future.delayed(Duration(milliseconds: 1500), () {
                                                // final provider = Provider.of<GraphDataProvider>(context, listen: false);
                                              });
              
                                            }, iconData: Icons.usb),
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
                            onTapButton: () {
                              print("STATUS RECORDING: $isRecording");
                              if (isRecording == 0) {
                                print("!!!INIT NWB FILE, $_sampleRate, ${_channelCount.length}");
                                
                                bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
                                if (isAudioListen) {
                                  GraphTemplate.nwbFileUtil?.processingInit(_sampleRate, widget.channelCount, "Audio|||", "SpikeRecorder Systems");
                                } else {
                                  GraphTemplate.nwbFileUtil?.processingInit(_sampleRate, widget.channelCount, "SpikeRecorder Device|||", "SpikeRecorder Systems");
                                }
                                Future.delayed(Duration(milliseconds: 1000), () {
                                  isRecording = 1;
                                });
                                // isRecording = 1;
                                
                              } else {
                                if (isRecording == 1) {
                                  isRecording = 2;
                                } else {
                                  isRecording = 0;
                                }
                              }
                            },
                            iconData: Icons.fiber_manual_record,
                            iconColor: Colors.red,
                          ),
                          const SizedBox(
                            width: 10,
                          ),
                          if (isRecording != 1) ... {
                            SpikerBoxButton(onTapButton: () async {
                              
                              startOpeningFile();

                            }, iconData: Icons.menu)
                          },
                        ],
                      )
                    ],
                  ),
                  BottomButtons(
                    pauseButton: (bool isPlay) async {
                      print("setGraphResumePlay PLAYBACK PAUSE BUTTON");
                      Provider.of<GraphResumePlayProvider>(context, listen: false).setGraphResumePlay(isPlay);
                      _toPauseGraph = isPlay;
                      GraphTemplate.isPlayerPaused = !isPlay;


                      if (soloud == null) {
                        soloud = SoLoud.SoLoud.instance;
                        await soloud!.init(
                          sampleRate: _sampleRate,
                          channels: SoLoud.Channels.mono,
                        );
                      }
                      bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
                      print("IS PLAY $isPlay");
                      if (!isPlay) {
                        print("STOP SOUND");
                        for (int i = 0; i < widget.channelCount; i++) {
                          soloud?.setDataIsEnded(loadedFileStreams[i]!);
                          soloud?.stop(loadedSoundHandles[i]!);
                        }
                        timerPlaybackLoadedFile?.cancel();
                        GraphTemplate.isLoadingFile = 2;
                      } else {
                        
                        loadedFileStreams.clear();
                        print("ADDED FILE STREAMS : $_sampleRate");
                        for (int i = 0; i < widget.channelCount; i++) {
                          loadedFileStreams.add(soloud!.setBufferStream(
                            // maxBufferSizeBytes: 1024 * 1024 * 2,
                            bufferingType: SoLoud.BufferingType.released,
                            sampleRate: _sampleRate,
                            channels: SoLoud.Channels.mono,
                            format: SoLoud.BufferType.s16le,
                            onBuffering: (isBuffering, handle, time) async {
                              if (context.mounted) {

                              }
                            },                          
                          ));
                        }
                        
                        
                        // insert old samples, if samplesLength == 0 return null,
                        double startSeekSample = startSeekSampleIdx.toDouble();
                        double maxScreenSamples = ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate; 
                        double endSeekSample = 0; // (arrSamplesLength - startSeekSample).floor()
                        print("TIME 0 $startSeekSample | $maxScreenSamples | $loadedMaxSamples | $endSeekSample");
                        // scenario 1: 3 seconds recorded audio : start 0 => END 210000
                        // scenario 2: 700000 samples recorded audio : start 200000 => END 680000  
                        if (loadedMaxSamples < maxScreenSamples) {
                          endSeekSample = loadedMaxSamples.toDouble();
                        } else {
                          if (startSeekSampleIdx + maxScreenSamples > loadedMaxSamples) {
                            endSeekSample = loadedMaxSamples.toDouble();
                          } else {
                            endSeekSample = loadedMaxSamples.toDouble();
                          }
                        }
                        startSeekSampleIdx = startSeekSample.floor();
                        // endSeekSampleIdx = endSeekSample.floor();
                        endSeekSampleIdx = (loadedMaxSamples - startSeekSample).floor();

                        Int32List arrSampleCount = Int32List(widget.channelCount);
                        // Int16List arrSamples = Int16List(loadedMaxSamples - startSeekSampleIdx);
                        Int16List arrSamples = Int16List(loadedMaxSamples * widget.channelCount);
                        // await GraphTemplate.nwbFileUtil?.seekElectricalSeries(arrSamples, arrSampleCount, loadedConfig, (startSeekSample).floor(), endSeekSample.floor(), 0, 1);
                        // await GraphTemplate.nwbFileUtil?.seekElectricalSeries(arrSamples, arrSampleCount, loadedConfig, (startSeekSample).floor(), (loadedMaxSamples).floor(), 0, 1);
                        print("======SEEK 1 ");
                        await GraphTemplate.nwbFileUtil?.seekElectricalSeries(arrSamples, arrSampleCount, loadedConfig, (startSeekSampleIdx).floor(), (loadedMaxSamples).floor(), 0, 0);
                        // loadedArrSamples = Int16List(arrSampleCount[0].floor());
                        // loadedArrSamples.setAll(0, arrSamples.sublist(0, arrSampleCount[0].floor()));
                        // loadedArrChannelCount.setAll(0, arrSampleCount);
                        // soloud!.addAudioDataStream(loadedFileStream!, loadedArrSamples.buffer.asUint8List());
                          // loadedArrChannelCount[i].fillRange(0, totalChannelCount, initialSampleCount.floor());
                        int combinedIdx = 0;
                        int totalChannelCount = loadedConfig[1];
                        loadedArrSamples.clear();
                        loadedArrChannelCount = (Int32List(widget.channelCount));
                        for (int i = 0; i < widget.channelCount; i++) {
                          // double initialSampleCount = arrSampleCount[i].floor() / totalChannelCount;
                          double initialSampleCount = arrSampleCount[i].toDouble();
                          loadedArrSamples.add(Int16List(initialSampleCount.floor()));
                          loadedArrSamples[i].setAll(0, arrSamples.sublist(combinedIdx, combinedIdx + initialSampleCount.floor()));
                          // loadedArrChannelCount.fillRange(0, totalChannelCount, initialSampleCount.floor());
                          loadedArrChannelCount[i] = initialSampleCount.floor();
                          combinedIdx += initialSampleCount.floor();
                          soloud!.addAudioDataStream(loadedFileStreams[i]!, loadedArrSamples[i].buffer.asUint8List());
                        }

                        print("ADDED DATA STREAM");

                        timerPlaybackLoadedFile?.cancel();
                        timerPlaybackLoadedStartIndex = 0;
                        timerPlaybackLoadedEndIndex = 0;
                        int rawSampleDivider = 128;
                        double playbackFactor = _sampleRate / 1000 ;
                        // 1000 *  1000 /48000
                        int initialStartSeekSampleIdx = startSeekSampleIdx;
                        int loadedMaxSamplesPlayback = loadedMaxSamples - startSeekSampleIdx;
                        Future.delayed(Duration(milliseconds: 100), () {
                          int prevTime = DateTime.now().millisecondsSinceEpoch;
                          // timerPlaybackLoadedFile = Timer.periodic(Duration(microseconds: (1000000 / (_sampleRate / rawSampleDivider)).floor()), (timer) async {
                          timerPlaybackLoadedFile = Timer.periodic(Duration(milliseconds: (50).floor()), (timer) async {
                            GraphTemplate.isLoadingFile = 4;
                            int timeDiff = DateTime.now().millisecondsSinceEpoch - prevTime;
                            int sampleDivider = (timeDiff * playbackFactor).floor();
                            prevTime = DateTime.now().millisecondsSinceEpoch;
                            try {
                              timerPlaybackLoadedEndIndex = timerPlaybackLoadedStartIndex + sampleDivider;
                              if (timerPlaybackLoadedEndIndex > loadedMaxSamplesPlayback) {
                                timerPlaybackLoadedEndIndex = loadedMaxSamplesPlayback - 1;
                              }

                              // MULTI CHANNEL FIXES.
                              List<Uint8List> sublistArray = [];
                              for (int i = 0; i < widget.channelCount; i++) {
                                if (isAudioListen) {
                                  sublistArray.add(loadedArrSamples[i].sublist(timerPlaybackLoadedStartIndex, timerPlaybackLoadedEndIndex).buffer.asUint8List());
                                } else {
                                  sublistArray.add(loadedArrSamples[i].sublist(0, timerPlaybackLoadedEndIndex).buffer.asUint8List());
                                }
                                // soloud!.addAudioDataStream(loadedFileStream!, sublistArray);
                              }
                              timerPlaybackLoadedStartIndex = (timerPlaybackLoadedStartIndex + sampleDivider);
                              if (timerPlaybackLoadedStartIndex > loadedMaxSamplesPlayback) {
                                timerPlaybackLoadedStartIndex = loadedMaxSamplesPlayback - 1;

                                double startSeekSampleLocal = endSeekSampleIdx.toDouble();
                                double endSeekSampleLocal = (loadedMaxSamples).toDouble(); // (arrSamplesLength - startSeekSample).floor()
                                startSeekSampleIdx = startSeekSample.floor();
                                endSeekSampleIdx = endSeekSample.floor();

                                print("ARR SAMPLES ZERO");
                                Int32List arrSampleCount = Int32List(widget.channelCount);
                                Int16List arrSamples = Int16List( (endSeekSampleIdx - startSeekSampleIdx) * widget.channelCount );
                                await GraphTemplate.nwbFileUtil?.seekElectricalSeries(arrSamples, arrSampleCount, loadedConfig, (startSeekSampleLocal).floor(), endSeekSampleLocal.floor(), 0, widget.channelCount - 1);
                                GraphTemplate.isLoadingFile = 2;
                                GraphTemplate.isPlayerPaused = true;

                                Provider.of<GraphResumePlayProvider>(context, listen: false).setGraphResumePlay(true);

                                timerPlaybackLoadedStartIndex = 0;
                                timerPlaybackLoadedEndIndex = 0;
                                startSeekSampleIdx = startSeekSample.floor();
                                endSeekSampleIdx = endSeekSample.floor();
                                

                                double playbackPercentage = (timerPlaybackLoadedStartIndex) / (loadedMaxSamplesPlayback);
                                AdaptiveAreaState.horizontalDragX = playbackPercentage * AdaptiveAreaState.horizontalDragXFix;                                
                                timerPlaybackLoadedFile?.cancel();
                                return;
                              }

                              GraphTemplate.isLoadingFile = 3;
                              // print("IS AUDIO LISTEN: $isAudioListen");
                              if (isAudioListen) {
                                processingUtil.processMicrophoneData(sublistArray[0]);
                                microphoneUtil.micStream.value = Uint8List(0);
                              } else {
                                int channelIdx = 0;
                                Int32List samplesCount = Int32List(sublistArray.length);
                                Int16List flattenedList = Int16List.fromList(sublistArray.expand((list) {
                                  samplesCount[channelIdx] = sublistArray[channelIdx].length;
                                  // print("SAMPLES COUNT: ${samplesCount[channelIdx]}");
                                  channelIdx++;
                                  return list.buffer.asInt16List();
                                }).toList());

                                // print("FLATTENED LIST: ${flattenedList.length} || $samplesCount");

                                // processingUtil.processingNwbFileInjectData(flattenedList, samplesCount, deviceType, drawSurfaceWidth, provider);
                                // processingUtil.processingNwbFileInjectData(flattenedList, samplesCount, 0, widget.channelCount);
                                processingUtil.processingSerialDataResult(flattenedList, samplesCount, widget.channelCount);
                              }

                              double playbackPercentage = (timerPlaybackLoadedStartIndex) / (loadedMaxSamplesPlayback);
                              // print("PLAYBACK PERCENTAGE: $playbackPercentage : $timerPlaybackLoadedStartIndex || $timerPlaybackLoadedEndIndex || $loadedMaxSamplesPlayback");
                              AdaptiveAreaState.horizontalDragX = playbackPercentage * AdaptiveAreaState.horizontalDragXFix;
                              setState(() {});
                            }catch(err) {     
                              // timerPlaybackLoadedFile?.cancel();                                 
                              // print("ERR: $err ||| $timerPlaybackLoadedEndIndex | $timerPlaybackLoadedStartIndex | $loadedMaxSamplesPlayback");
                            }                            

                          });
                          
                          loadedSoundHandles.clear();
                          for (int i = 0; i < widget.channelCount; i++) {
                            soloud!.play(loadedFileStreams[i]!).then((soundHandle) {
                              loadedSoundHandles.add(soundHandle);
                              // loadedSoundHandles[i] = soundHandle;
                            });
                          }
                        });
                        
                        print("ADDED DATA STREAM2");


                        GraphTemplate.isLoadingFile = 3;
                        loadedConfig[7] = MediaQuery.of(context).size.width.toInt();
                        await processingUtil.initWithConfig(loadedConfig);
                        print("START SEEK SAMPLE INITIAL 0000 $startSeekSampleIdx ${arrSampleCount[0].floor()} == $loadedMaxSamples");
                        if (startSeekSampleIdx > 0 && arrSampleCount[0].floor() > 0) {
                          int startInitialIndex = (startSeekSampleIdx ~/ maxScreenSamples.floor()) * maxScreenSamples.floor();
                          int endInitialIndex = (startSeekSample % maxScreenSamples.floor()).floor();
                          // int endInitialIndex = 240000;
                          Int32List arrSampleCountInitial = Int32List(widget.channelCount);
                          Int16List arrSamplesInitial = Int16List(endInitialIndex * widget.channelCount);
                          await GraphTemplate.nwbFileUtil?.seekElectricalSeries(arrSamplesInitial, arrSampleCountInitial, loadedConfig, startInitialIndex, endInitialIndex, 0, 0);

                          Int16List tempLoadedArrSamples = Int16List(arrSampleCountInitial[0].floor());
                          tempLoadedArrSamples.setAll(0, arrSamplesInitial.sublist(0, arrSampleCountInitial[0].floor()));
                          print("----> START SEEK SAMPLE INITIAL : $startInitialIndex |=| ${(startSeekSample % maxScreenSamples.floor()).floor()} | ${arrSampleCountInitial[0].floor()} |  ${tempLoadedArrSamples.length} |||| ${tempLoadedArrSamples.buffer.asUint8List().length}");
                          // GraphTemplate.isLoadingFile = 3;

                          processingUtil.processMicrophoneData(tempLoadedArrSamples.buffer.asUint8List());
                          // microphoneUtil.micStream.value = tempLoadedArrSamples.buffer.asUint8List();
                          microphoneUtil.micStream.value = Uint8List(0);
                        } else {
                          GraphTemplate.isLoadingFile = 4;
                          // microphoneUtil.micStream.value = Uint8List(0);
                        }
                        

                        // soloud!.addAudioDataStream(loadedFileStream!, loadedArrSamples.buffer.asUint8List());
                      }
                    },
                  ),
                ],
              ),
            ),
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
                      arr = [processingUtil.thresholdingArraylength];

                      int drawSurfaceWidth = MediaQuery.of(context).size.width.toInt();
                      if (isDeviceConnect) {
                        _serialUtil.writeToPort(bytesMessage: UsbCommand.hwTypeInquiry.cmdAsBytes(), address: _availablePorts.last);
                        isDeviceConnect = false;
                      }
                      if (_isDataIdentified) {
                        if (!GraphTemplate.isPlayerPaused) {
                          processingUtil.processSerialData(event, displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider).then((samples) {
                            totalSampleCount += samples[0].length;
                            if (totalSampleCount > sampleCountToDisplay) {
                              totalSampleCount = 0;
                              if (isThresholdingButton) {
                                double displayTimeDivision = (displayTimeMs / 10000);
                                double gap = (arr[0] * (1 - displayTimeDivision));
                                int maxSamples = (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
                                int toSample = maxSamples - (gap/2).floor();
                                int fromSample = toSample - arr[0] + (gap).floor();
                                DraggableGraph.startPositionIdx = fromSample;
                                DraggableGraph.endPositionIdx = toSample;

                                processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider, fromSample, toSample);
                              } else {
                                int maxSamples = (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
                                int maxDisplaySamples = (displayTimeMs * 0.001 * _sampleRate).floor();
                                DraggableGraph.startPositionIdx = maxSamples - maxDisplaySamples;
                                DraggableGraph.endPositionIdx = maxSamples;

                                processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider, 0, maxDisplaySamples);
                              }
                            }
                          });
                        } else {
                          if (SoundWaveView.dragDetails != null) {
                            // int fromSample = (-bufferPaddingLeft).toInt();
                            // int toSample = (fromSample + displayTimeMs * 0.001 * _sampleRate).toInt();
                            totalSampleCount += 2;
                            if (totalSampleCount > sampleCountToDisplay) {
                              totalSampleCount = 0;

                              int maxSamples = (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
                              int toSample = (maxSamples + bufferPaddingLeft).toInt();
                              toSample = min(maxSamples, toSample);
                              int fromSample = (toSample - displayTimeMs * 0.001 * _sampleRate).toInt();
                              DraggableGraph.startPositionIdx = fromSample;
                              DraggableGraph.endPositionIdx = toSample;


                              // processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, fromSample, toSample );
                              if (isThresholdingButton) {
                                double displayTimeDivision = (displayTimeMs / 10000);
                                double gap = (arr[0] * (1 - displayTimeDivision));
                                toSample = maxSamples - (gap/2).floor();
                                fromSample = toSample - arr[0] + (gap).floor();
                                processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider, fromSample, toSample);
                              } else {
                                processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider, fromSample, toSample);
                              }
                            }
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
                          // processingUtil.processSerialData(event, displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider).then((sampleCount) {
                          //   totalSampleCount += sampleCount;
                          processingUtil.processSerialData(event, displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider).then((samples) {
                            totalSampleCount += samples[0].length;
                            if (totalSampleCount > sampleCountToDisplay) {
                              totalSampleCount = 0;
                              if (isThresholdingButton) {
                                double displayTimeDivision = (displayTimeMs / 10000);
                                double gap = (arr[0] * (1 - displayTimeDivision));
                                int maxSamples = (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
                                int toSample = maxSamples - (gap/2).floor();
                                int fromSample = toSample - arr[0] + (gap).floor();
                                DraggableGraph.startPositionIdx = fromSample;
                                DraggableGraph.endPositionIdx = toSample;
                                processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider, fromSample, toSample);
                              } else {
                                int maxSamples = (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
                                int maxDisplaySamples = (displayTimeMs * 0.001 * _sampleRate).floor();
                                DraggableGraph.startPositionIdx = maxSamples - maxDisplaySamples;
                                DraggableGraph.endPositionIdx = maxSamples;

                                processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider, 0, (maxDisplaySamples).floor());
                              }
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
    getData = await _serialUtil.openPortToListen(listOfPort.last, baudRate);
    bool dummyDataStatus = dataStatus.isSampleDataOn;
    bool isAudioListen = dataStatus.isMicrophoneData;
    dataStatus.setDeviceDataStatus(true);
    // var rng = Random();
    // List<int> initialSamples = [];
    // int headIdx = 0;
    // int headLimit = 4 * 20000;
    // if (initialSamples.isEmpty) {
    //   for (int i = 1; i < 20001; i++) {
    //     // initialSamples.addAll([255,255,1,1,128,255]);
    //     initialSamples.addAll([ 191, 20, 64, 115]);
    //     // initialSamples.addAll([0,10 * i,0,20 * i]);
    //     // initialSamples.addAll([0,10 * i,0,20 * i]);
    //     // initialSamples.addAll([255,255,1,1,129,255]);
    //   }
    // }
    // Uint8List initialSamplesArr = Uint8List.fromList(initialSamples);

    // Stopwatch stopwatch = Stopwatch();
    final provider = Provider.of<GraphDataProvider>(context, listen: false);
    totalSampleCount = 0;

    serialDataSubscription?.cancel();
    serialDataSubscription = getData?.listen((event) async {
      if (!isAudioListen) {
        final provider = Provider.of<GraphDataProvider>(context, listen: false);
        int drawSurfaceWidth = MediaQuery.of(context).size.width.toInt();
        if (isDeviceConnect) {
          _serialUtil.writeToPort(bytesMessage: UsbCommand.hwTypeInquiry.cmdAsBytes(), address: listOfPort.last);
          isDeviceConnect = false;
        }
        if (_isDataIdentified) {
          // print("GRAPHTEMPLATE IS LOADING FILE ${GraphTemplate.isLoadingFile}");
          serialNativeDataSubscription(event, isAudioListen);
        } else {
          if (!isDeviceConnect && !isDeviceSelected) {
            _preEscapeSequenceBuffer.addBytes(event);
          }
          if (isDeviceSelected) { // !isDeviceConnect &&
            _isDataIdentified = true;
            // STEVE
            if (!GraphTemplate.isPlayerPaused) {
              List<Int16List> samples = await processingUtil.processSerialData(event, displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider);
              int sampleCount = samples[0].length;

              if (isThresholdingButton) {
                int selectedChannel = context.read<ThresholdStatusProvider>().selectedThresholdChannel;
                bool isAverageSamples = true;
                processingUtil.processThresholdData(samples, samples.length, drawSurfaceWidth, selectedChannel, isAverageSamples);
              }

              totalSampleCount += sampleCount;
              if (totalSampleCount> sampleCountToDisplay) {
                totalSampleCount = 0;
                DraggableGraph.startPositionIdx = 0;
                DraggableGraph.endPositionIdx = (displayTimeMs * 0.001 * _sampleRate).floor();

                await processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider, 0, (displayTimeMs * 0.001 * _sampleRate).floor());
                provider.inputListener(Uint8List(0));
              }
            } else {
              // await processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider);
              // int fromSample = (-bufferPaddingLeft).toInt();
              // int toSample = (fromSample + displayTimeMs * 0.001 * _sampleRate).toInt();
              int maxSamples = (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
              int toSample = (maxSamples + bufferPaddingLeft).toInt();
              toSample = min(maxSamples, toSample);
              int fromSample = (toSample - displayTimeMs * 0.001 * _sampleRate).toInt();
              DraggableGraph.startPositionIdx = fromSample;
              DraggableGraph.endPositionIdx = toSample;

              // processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, fromSample, toSample );
              await processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider, fromSample, toSample);

              provider.inputListener(Uint8List(0));
            }


          }
        }
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
  
  bool isThresholdingButton = false;
  bool isFftButton = false;
  
  bool isChoosingThresholdType = false;
  
  TextEditingController thresholdValueController = TextEditingController();
  
  List<String> listMenuOptions = ["Ev", "E1", "E2", "E3", "E4", "E5", "E6", "E7", "E8", "E9"];
  List<String> listMenuLabels = ["Signal", "E1", "E2", "E3", "E4", "E5", "E6", "E7", "E8", "E9", "Ev"];
  
  String eventThresholdTriggeredType = "Signal";

  
  void listenToMicrophone(channelCount, provider) {
    if (provider == null) {
      provider = Provider.of<GraphDataProvider>(context, listen: false);      
    }
    isDeviceConnect = true;
    isDeviceSelected = false;
    _isDataIdentified = false;
    deviceChannelCount = channelCount;
    foundDevices = "";
    Future.delayed(const Duration(seconds: 2)).then((value) async {
      // print("_messageIdentifier.messageState");
      // print(_messageIdentifier.messageState);
      // Initialize both utils
      try{
        microphoneUtil.micStream.removeListener(micListener);
        microphoneUtil.micStream = ValueNotifier(Uint8List(0));
        context.read<DataStatusProvider>().setMicrophoneDataStatus(true);
        print("LISTEN TO MICROPHONE setMicrophoneDataStatus");
        Provider.of<ConstantProvider>(context, listen: false).setChannelCount(channelCount);
        Provider.of<SampleRateProvider>(context, listen: false).setSampleRate(microphoneUtil.sampleRate.floor());

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
        print("NATIVE SAMPLE RATE : ${microphoneUtil.sampleRate}");
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
      ProcessingUtil.initializeDevice.value = 0;

    });
  }

  List<int> arr = [];
  
  int thresholdSliderValue = 1;
  
  double FFT_WIDGET_HEIGHT = 0.3;
  
  int FFT_30HZ_LENGTH = 32;
  int FFT_WINDOW_TIME_LENGTH = 4;
  
  int isRecording = 0;
  
  Timer? timerPlaybackLoadedFile;
  int timerPlaybackLoadedStartIndex = 0;
  int timerPlaybackLoadedEndIndex = 0;
  int loadedMaxSamples = 0;
  Int32List loadedConfig = Int32List(10);
  List<Int16List> loadedArrSamples = [];
  Int32List loadedArrChannelCount = Int32List(1);

  int startSeekSampleIdx = 0;
  int endSeekSampleIdx = 0;
  
  ValueNotifier<List<int>> scrubNotifier = ValueNotifier([]);
  SoLoud.SoLoud? soloud;
  List<SoLoud.AudioSource?> loadedFileStreams = [];
  
  List<SoLoud.SoundHandle?> loadedSoundHandles = [];
  
  bool isOpeningFile = false;
  
  Stream<Uint8List>? getData;
  
  Timer? periodicTimerSerial;
  

  void micListener(){
    // print("miCLISTENER DATA");
    int channelCount = 1;
    int selectedThresholdChannel = 0;
    final provider = Provider.of<GraphDataProvider>(context, listen: false);

    bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
    // print("isAUDIO LISTEN: $isAudioListen GraphTemplate.isLoadingFile: ${GraphTemplate.isLoadingFile}");
    if (isAudioListen) {
      if (GraphTemplate.isLoadingFile == 2  || GraphTemplate.isLoadingFile == 4) {
        int drawSurfaceWidth = MediaQuery.of(context).size.width.toInt();
        // int maxSamples = (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
        // int maxDisplaySamples = (displayTimeMs * 0.001 * _sampleRate).floor();
        // DraggableGraph.startPositionIdx = maxSamples - maxDisplaySamples;
        // DraggableGraph.endPositionIdx = maxSamples;
        // processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, 0, maxDisplaySamples );

        int maxSamples = (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
        // int maxSamples = loadedMaxSamples;
        int toSample = (maxSamples + bufferPaddingLeft).toInt();
        toSample = min(maxSamples, toSample);
        int fromSample = (toSample - displayTimeMs * 0.001 * _sampleRate).toInt();
        processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, fromSample, toSample );

        

        // print("RANGE MASK : ${DraggableGraph.startPositionIdx} -- ${DraggableGraph.endPositionIdx} || ${maxDisplaySamples} || ${maxSamples} ${_sampleRate}");
      } else
      if (GraphTemplate.isLoadingFile == 1) {
        GraphTemplate.isLoadingFile = 2;
        // print("PROCESS MICROPHONE DATA LOADED 1: ${GraphTemplate.isLoadingFile} ${loadedArrChannelCount[0]} ${loadedArrSamples.length} ");
        // List<Int16List> tempData = processingUtil.processMicrophoneData(loadedArrSamples.sublist(0, loadedArrChannelCount[0]).buffer.asUint8List());
        List<Int16List> tempData = processingUtil.processMicrophoneData(loadedArrSamples[0].buffer.asUint8List());
        // List<Int16List> tempData = processingUtil.processMicrophoneData(Uint8List(0));
        microphoneUtil.micStream.value = Uint8List(0);
      } else {
        if (GraphTemplate.isLoadingFile == 3) {
            GraphTemplate.isLoadingFile = 4;
            // print("PROCESS MICROPHONE DATA LOADED 3: ${GraphTemplate.isLoadingFile}");
            processingUtil.processMicrophoneData(microphoneUtil.micStream.value);        
        } else 
        if (!GraphTemplate.isPlayerPaused) {
          if (isThresholdingButton) {
            if (kIsWeb) {
              processingUtil.processMicrophoneData(microphoneUtil.micStream.value);           
            } else {
              List<Int16List> tempData = processingUtil.processMicrophoneData(microphoneUtil.micStream.value);
              tempData.add(Int16List.fromList(tempData[0]));
              Int32List samplesCount = Int32List(tempData.length);
              
              // int counterLen = 0;
              int channelIdx = 0;
              Int16List flattenedList = Int16List.fromList(tempData.expand((list) {
                samplesCount[channelIdx] = tempData[channelIdx].length;
                // counterLen += tempData[channelIdx].length;
                channelIdx++;
                return list;
              }).toList());

              if (isRecording == 1) {
                // print("GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 1, 0) 11 -- $isRecording ${samplesCount}");
                // STEVE
                GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 1, 0);
                // GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 2, 0);
              } else 
              if (isRecording == 2) {
                isRecording = 0;
                // STEVE
                // print("END RECORDING!!! GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 1, 1)");
                // print("GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 2, 1)");
                GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 1, 1);
              }
              bool isAverageSamples = true;
              arr = processingUtil.processThresholdData(tempData, tempData.length, MediaQuery.of(context).size.width.floor(), selectedThresholdChannel, isAverageSamples);
            }
          } else {
            // print("PROCESS MICROPHONE DATA LOADED 4 : ${GraphTemplate.isLoadingFile}");            
            List<Int16List> tempData = processingUtil.processMicrophoneData(microphoneUtil.micStream.value); 
            tempData.add(Int16List.fromList(tempData[0]));
            Int32List samplesCount = Int32List(tempData.length * widget.channelCount);
            
            int counterLen = 0;
            int channelIdx = 0;
            Int16List flattenedList = Int16List.fromList(tempData.expand((list) {
              samplesCount[channelIdx] = tempData[channelIdx].length;
              counterLen += tempData[channelIdx].length;
              channelIdx++;
              return list;
            }).toList());

            if (isRecording == 1) {
              // print("GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 2, 0) 22 -- $isRecording");
              // STEVE
              GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 1, 0);
              // GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 2, 0);
            } else 
            if (isRecording == 2) {
              isRecording = 0;
              print("ENDING RECORDING GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 2, 1)");
              // STEVE
              GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 1, 1);
              // GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 2, 1);
            }

            // if (isFftButton) {
            if (!kIsWeb) {
              int windowCount = ( (10.0 * 128) / (512 * 0.01).floor() ).floor();
              int windowSize = (FFT_30HZ_LENGTH * FFT_WINDOW_TIME_LENGTH);
              List<int> inSampleCounts = [];
              // print("KISWEB inSampleCounts: ${tempData[0].length}");
              for (var data in tempData){
                inSampleCounts.add(data.length);
              }
              processingUtil.processFftMicrophoneData(tempData, [windowCount], [windowSize], inSampleCounts, channelCount);            
            }
            // }
          }
        }
        // _preGraphBuffer.addBytes(event);

        // if (drawIdx == 3) {
        int drawSurfaceWidth = MediaQuery.of(context).size.width.toInt() * MediaQuery.of(context).devicePixelRatio.toInt() ;
        // print("Pixel Ratio: ${MediaQuery.of(context).devicePixelRatio.toInt()}");
        // int drawSurfaceWidth = MediaQuery.of(context).size.width.toInt();
        // print("Pixel Ratio: ${MediaQuery.of(context).size.width.toInt()} --- ${MediaQuery.of(context).devicePixelRatio.toInt()}");
        if (!GraphTemplate.isPlayerPaused) {
          if (isThresholdingButton) {
            if (kIsWeb) {
              arr = [processingUtil.thresholdingArraylength];
            }
            double displayTimeDivision = (displayTimeMs / 10000);
            double gap = (arr[0] * (1 - displayTimeDivision));
            int maxSamples = (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
            int toSample = maxSamples - (gap/2).floor();
            int fromSample = toSample - arr[0] + (gap).floor();
            // print("GAP THRESHOLD: $gap - Start : $fromSample -- (${(gap/2).floor()}) - END: $toSample -- ${ (arr[0]-gap/2).floor() }");
            DraggableGraph.startPositionIdx = fromSample;
            DraggableGraph.endPositionIdx = toSample;
            processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, fromSample, toSample );
            // processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, (0 + gap/2).floor(), (arr[0] - gap/2).floor() );
          } else {
            // DraggableGraph.startPositionIdx = 0;
            // DraggableGraph.endPositionIdx = (displayTimeMs*0.001 * microphoneUtil.sampleRate).floor();
            int maxSamples = (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
            int maxDisplaySamples = (displayTimeMs * 0.001 * _sampleRate).floor();
            DraggableGraph.startPositionIdx = maxSamples - maxDisplaySamples;
            DraggableGraph.endPositionIdx = maxSamples;
            // print("RANGE MASK :");
            // print("RANGE MASK : ${DraggableGraph.startPositionIdx} -- ${DraggableGraph.endPositionIdx} || ${maxDisplaySamples} || ${maxSamples}");
            // print("PROCESS MICROPHONE DATA LOADED 3: PREPARE DISPLAY MICROPHONE DATA");
            processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, 0, maxDisplaySamples );
            if (isFftButton ) {
              Size screenSize = MediaQuery.of(context).size;
              // int windowCount = processingUtil.window_count[0];
              // double windowSize = processingUtil.window_size[0].toDouble();
              // processingUtil.prepareForFftDrawing(windowCount, windowSize.floor(), screenSize.width.toInt(), (screenSize.height * FFT_WIDGET_HEIGHT).toInt());
              int maxWindowCount = ( (10.0 * 128) / (512 * 0.01).floor() ).floor() ;
              int windowCount = maxWindowCount;
              int drawEndIndex = DraggableGraph.endPositionIdx;
              int drawStartIndex = DraggableGraph.startPositionIdx;
              // double drawWidthMax = maxDisplaySamples.toDouble();
              // int targetWindowCount = (maxWindowCount * (drawEndIndex - drawStartIndex) / drawWidthMax).floor();
              int targetWindowCount = (maxWindowCount * (drawEndIndex - drawStartIndex) / maxSamples).floor();

              // double windowSize = MediaQuery.of(context).size.height * FFT_WIDGET_HEIGHT;
              int windowSize = (FFT_30HZ_LENGTH * FFT_WINDOW_TIME_LENGTH);
              // print("CALCULATION1: (maxWindowCount * (drawEndIndex - drawStartIndex) / drawWidthMax).floor()");
              // print("CALCULATION2: (${drawEndIndex - drawStartIndex})");
              // print("CALCULATION3: ($maxWindowCount * ($drawEndIndex - $drawStartIndex) / $maxSamples).floor() = $targetWindowCount :: $maxSamples");
              // print("INDEX: $drawStartIndex -- $drawEndIndex : $drawWidthMax $targetWindowCount vs $windowCount");
              // jint maxWindowCount = env->GetArrayLength(in);
              // jint windowCount = static_cast<jint>(maxWindowCount * (drawEndIndex - drawStartIndex) /
              //                                      drawWidthMax);
              processingUtil.prepareForFftDrawing(windowCount, windowSize, targetWindowCount, screenSize.width, (screenSize.height * FFT_WIDGET_HEIGHT));
            }
          }
        } else {
          double startElementIdx = 0.0;

          // if (ProcessingUtil.positionIndex > 0) {
            if (SoundWaveView.dragDetails != null) {
              if (kIsWeb) {
                arr = [processingUtil.thresholdingArraylength, processingUtil.thresholdingArraylength];
              }

              // int level = calculateLevel(displayTimeMs, _sampleRate.toDouble(), drawSurfaceWidth.toDouble(), arrCounts, 0);
              // double divider = ;
              // print("bufferPaddingLeft : $bufferPaddingLeft");
              // int fromSample = (ProcessingUtil.positionIndex - displayTimeMs * 0.001 * _sampleRate - bufferPaddingLeft).toInt();
              // int fromSample = (-bufferPaddingLeft).toInt();
              // int toSample = (fromSample + displayTimeMs * 0.001 * _sampleRate).toInt();
              int maxSamples = (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
              int toSample = (maxSamples + bufferPaddingLeft).toInt();
              toSample = min(maxSamples, toSample);
              int fromSample = (toSample - displayTimeMs * 0.001 * _sampleRate).toInt();
              // int toSample = (displayTimeMs * 0.001 * _sampleRate).toInt();
              // print("fromSample - toSample : $fromSample _ $toSample  ${bufferPaddingLeft} ${displayTimeMs * 0.001 * _sampleRate} ${bufferPos[1]}");
              if (isThresholdingButton) {
                // processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, 0, arr[0] );

                double displayTimeDivision = (displayTimeMs / 10000);
                double gap = (arr[0] * (1 - displayTimeDivision));
                int maxSamples = (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
                int toSample = maxSamples - (gap/2).floor();
                int fromSample = toSample - arr[0] + (gap).floor();

                DraggableGraph.startPositionIdx = fromSample;
                DraggableGraph.endPositionIdx = toSample;
                processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, fromSample, toSample );
                // processingUtil.prepareDisplayMicrophoneThresholdData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, arr[0], (0 + gap/2).floor(), (arr[0] - gap/2).floor() );
                // processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, (0 + gap/2).floor(), (arr[0] - gap/2).floor() );

              } else {
                DraggableGraph.startPositionIdx = fromSample;
                DraggableGraph.endPositionIdx = toSample;
                processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, fromSample, toSample );
              }
            } else {
              // processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, 0, 10 * _sampleRate );
              if (isThresholdingButton) {
                DraggableGraph.startPositionIdx = 0;
                DraggableGraph.endPositionIdx = arr[0];
                processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, 0, arr[0] );
              } else {
              }
            }


            if (isFftButton) {
              Size screenSize = MediaQuery.of(context).size;
              int maxWindowCount = ( (10.0 * 128) / (512 * 0.01).floor() ).floor() ;
              int maxSamples = (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();

              int windowCount = maxWindowCount;
              int drawEndIndex = DraggableGraph.endPositionIdx;
              int drawStartIndex = DraggableGraph.startPositionIdx;
              int targetWindowCount = (maxWindowCount * (drawEndIndex - drawStartIndex) / maxSamples).floor();

              int windowSize = (FFT_30HZ_LENGTH * FFT_WINDOW_TIME_LENGTH);            
              print("prepareForFftDrawing wc: $windowCount ws:$windowSize twc:$targetWindowCount ${screenSize.width} ${screenSize.height * FFT_WIDGET_HEIGHT}");
              processingUtil.prepareForFftDrawing(windowCount, windowSize, targetWindowCount, screenSize.width, (screenSize.height * FFT_WIDGET_HEIGHT));
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
  
  void startOpeningFile() async {
    print("INIT NWB FILE");
    isOpeningFile = true;
    Int32List arrConfig = Int32List(10);
    Int32List arrSampleCount = Int32List(widget.channelCount);
    Int16List arrSamples = Int16List(1);
    // await GraphTemplate.nwbFileUtil?.readElectricalSeries(arrSampleCount, arrChannelCount, 0, 1);
    // DEMO
                        print("======SEEK OPEN FILE");
    await GraphTemplate.nwbFileUtil?.seekElectricalSeries(arrSamples, arrSampleCount, arrConfig, 0, 1, 0, 0);
    widget.channelCount = arrConfig[1];
    arrSampleCount = Int32List(widget.channelCount);
    loadedMaxSamples = arrConfig[5];
    int sampleRateConfig = arrConfig[0];
    
    loadedConfig.setAll(0, arrConfig);
    loadedMaxSamples = arrConfig[5];
    _sampleRate = sampleRateConfig;
    int isSerialDevice = arrConfig[6];
    print("IS SERIAL DEVICE : $isSerialDevice | CHANNEL COUNT: ${widget.channelCount}");
    if (isSerialDevice == 1) {
      // GraphTemplate.selectedBoard = Board(maxSampleRate: sampleRateConfig.toString(), maxNumberOfChannels: widget.channelCount.toString());
      // processingUtil.initializeSerial(GraphTemplate.selectedBoard!, MediaQuery.of(context).size.width);
      // if (context.mounted) {
        context.read<DataStatusProvider>().setMicrophoneDataStatus(false);
        Provider.of<ConstantProvider>(context, listen: false).setChannelCount(widget.channelCount);     
        Provider.of<SampleRateProvider>(context, listen: false).setSampleRate(sampleRateConfig);     
        ProcessingUtil.initializeDevice.value = 1;
        context.read<ChannelColorProvider>().setSerialChannelCount(
            widget.channelCount);

        periodicSerialDataSubscription();
      // }
    } else {
        context.read<DataStatusProvider>().setMicrophoneDataStatus(true);
        Provider.of<ConstantProvider>(context, listen: false).setChannelCount(widget.channelCount);     
        Provider.of<SampleRateProvider>(context, listen: false).setSampleRate(sampleRateConfig);     
        ProcessingUtil.initializeDevice.value = 0;
        context.read<ChannelColorProvider>().setAudioChannelCount(widget.channelCount);
        periodicTimerSerial?.cancel();

    }

    AdaptiveAreaState.maxTime = loadedMaxSamples / _sampleRate;
    // AdaptiveAreaState.strMaxTime = loadedMaxSamples / _sampleRate;
    
    print("sampleRateConfig: $sampleRateConfig $arrConfig");
    double arrSamplesLength = ProcessingUtil.MAX_DISPLAY_SECONDS * sampleRateConfig;
    // double arrSamplesLength = maxSamples.toDouble();
    
    // // Calculate total data points needed for multi-channel reading
    // int samplesPerChannel = arrSamplesLength.floor();
    // int numChannels = 2; // Reading channels 0-1
    // int totalDataPoints = samplesPerChannel * numChannels;

    arrSamples = Int16List(arrSamplesLength.floor() * widget.channelCount);

    // await GraphTemplate.nwbFileUtil?.seekElectricalSeries(arrSamples, arrSampleCount, arrConfig, 0, arrSamplesLength.floor(), 0, 1);
    double startSeekSample = 0;
    double endSeekSample = arrSamplesLength; // (arrSamplesLength - startSeekSample).floor()
    startSeekSampleIdx = startSeekSample.floor();
    endSeekSampleIdx = endSeekSample.floor();
    if (endSeekSampleIdx > loadedMaxSamples) {
      endSeekSampleIdx = loadedMaxSamples.floor();
      endSeekSample = loadedMaxSamples.toDouble();
    }

    await Future.delayed(Duration(milliseconds: 100));

    print("FINISH WAITINGGGGGG END SEEK SAMPLE IDX: $endSeekSampleIdx $loadedMaxSamples");
    await GraphTemplate.nwbFileUtil?.seekElectricalSeries(arrSamples, arrSampleCount, loadedConfig, (startSeekSample).floor(), endSeekSample.floor(), 0, widget.channelCount - 1);
    // print("Start Seek Sample: $startSeekSample --- End Seek Sample: $endSeekSample ||| arrSampleCount : ${arrSampleCount} ____ CHANNEL COUNT: ${widget.channelCount}");
    
    loadedConfig[7] = MediaQuery.of(context).size.width.toInt();
    processingUtil.initWithConfig(loadedConfig);
    // return;
    int combinedIdx = 0;
    int totalChannelCount = loadedConfig[1];
    loadedArrSamples.clear();
    loadedArrChannelCount = (Int32List(widget.channelCount));
    for (int i = 0; i < widget.channelCount; i++) {
      // double initialSampleCount = arrSampleCount[i].floor() / totalChannelCount;
      double initialSampleCount = arrSampleCount[i].toDouble();
      loadedArrSamples.add(Int16List(initialSampleCount.floor()));
      loadedArrSamples[i].setAll(0, arrSamples.sublist(combinedIdx, combinedIdx + initialSampleCount.floor()));
      // loadedArrChannelCount.fillRange(0, totalChannelCount, initialSampleCount.floor());
      loadedArrChannelCount[i] = initialSampleCount.floor();
      combinedIdx += initialSampleCount.floor();
    }    
    // print("loadedArrSamples1: ${loadedArrSamples[1]}");
    loadedConfig[7] = MediaQuery.of(context).size.width.toInt();
    processingUtil.initWithConfig(loadedConfig);

    GraphTemplate.isPlayerPaused = true;
    microphoneUtil.micStream.value = Uint8List(0);
    print("setGraphResumePlay PLAYBACK INIT");
    Provider.of<GraphResumePlayProvider>(context, listen: false).setGraphResumePlay(false);
    GraphTemplate.isLoadingFile = 1;
    
    // serialNativeDataSubscription(Uint8List(0), false);
    setState(() {     
    });
  }
  
  void serialNativeDataSubscription(Uint8List event, bool isAudioListen) async {
    final provider = Provider.of<GraphDataProvider>(context, listen: false);
    int drawSurfaceWidth = MediaQuery.of(context).size.width.toInt();
    
    if (GraphTemplate.isLoadingFile == 2  || GraphTemplate.isLoadingFile == 4) {
      int maxSamples = (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
      int toSample = (maxSamples + bufferPaddingLeft).toInt();
      toSample = min(maxSamples, toSample);
      int fromSample = (toSample - displayTimeMs * 0.001 * _sampleRate).toInt();
      await processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider, fromSample, toSample);
      setState(() {     
      });
    } else
    if (GraphTemplate.isLoadingFile == 1) {
      print("Graph Template: ${GraphTemplate.isLoadingFile}");
      GraphTemplate.isLoadingFile = 2;
      // SERIAL FILE CHANGES
      // List<Int16List> tempData = processingUtil.processMicrophoneData(loadedArrSamples[0].buffer.asUint8List());
      int channelIdx = 0;
      Int32List samplesCount = Int32List(loadedArrSamples.length);
      Int16List flattenedList = Int16List.fromList(loadedArrSamples.expand((list) {
        samplesCount[channelIdx] = loadedArrSamples[channelIdx].length;
        channelIdx++;
        return list;
      }).toList());
      // print("loadedArrSamples: ${loadedArrSamples.sublist(0, 10)}");
      // print("SAMPLES COUNT: $samplesCount");
      // print("WIDGET CHANNEL COUNT: $widget.channelCount");
      processingUtil.processingNwbFileInjectData(flattenedList, samplesCount, 0, widget.channelCount);
    } else
    if (GraphTemplate.isLoadingFile == 3) {
      // SERIAL FILE CHANGES
      // processingUtil.processMicrophoneData(microphoneUtil.micStream.value);
      // List<Int16List> samples = await processingUtil.processSerialData(event, displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider);

      // int channelIdx = 0;
      // Int32List samplesCount = Int32List(loadedArrSamples.length);
      // Int16List flattenedList = Int16List.fromList(loadedArrSamples.expand((list) {
      //   samplesCount[channelIdx] = loadedArrSamples[channelIdx].length;
      //   channelIdx++;
      //   return list;
      // }).toList());


      // processingUtil.processingNwbFileInjectData(flattenedList, samplesCount, 0, widget.channelCount);
      GraphTemplate.isLoadingFile = 4;

    } else {
      if (!GraphTemplate.isPlayerPaused) {
        List<Int16List> samples = await processingUtil.processSerialData(event, displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider);
        
        int channelIdx = 0;
        Int32List samplesCount = Int32List(samples.length);
        Int16List flattenedList = Int16List.fromList(samples.expand((list) {
          samplesCount[channelIdx] = samples[channelIdx].length;
          channelIdx++;
          return list;
        }).toList());
        if (isRecording == 1) {
          // print("GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, ${widget.channelCount}, 0) 11 -- $isRecording ${samplesCount}");
          // STEVE
          GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, widget.channelCount, 0);
          // GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 2, 0);
        } else 
        if (isRecording == 2) {
          // STEVE
          // print("END RECORDING!!! GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, ${widget.channelCount}, 1)");
          // print("GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 2, 1)");
          GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, widget.channelCount, 1);
          isRecording = 0;
        }


        // print("Zamples: $samples && ");
        int sampleCount = samples[0].length;
        if (isThresholdingButton) {
          if (kIsWeb) {
          } else {
            int selectedChannel = context.read<ThresholdStatusProvider>().selectedThresholdChannel;
            bool isAverageSamples = true;
            arr = processingUtil.processThresholdData(samples, samples.length, drawSurfaceWidth, selectedChannel, isAverageSamples);
          }
        }

        totalSampleCount += sampleCount;
        if (totalSampleCount > sampleCountToDisplay) {
          totalSampleCount = 0;
          if (isThresholdingButton) {
            double displayTimeDivision = (displayTimeMs / 10000);
            double gap = (arr[0] * (1 - displayTimeDivision));
            int maxSamples = (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
            int toSample = maxSamples - (gap/2).floor();
            int fromSample = toSample - arr[0] + (gap).floor();
            DraggableGraph.startPositionIdx = fromSample;
            DraggableGraph.endPositionIdx = toSample;
            await processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider, fromSample, toSample);
          } else {
            int maxSamples = (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
            int maxDisplaySamples = (displayTimeMs * 0.001 * _sampleRate).floor();
            DraggableGraph.startPositionIdx = maxSamples - maxDisplaySamples;
            DraggableGraph.endPositionIdx = maxSamples;
            await processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider, 0, maxDisplaySamples);                
          }
          // await processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider);
          provider.inputListener(Uint8List(0));
        }
      } else {
        if (isThresholdingButton) {
          double displayTimeDivision = (displayTimeMs / 10000);
          double gap = (arr[0] * (1 - displayTimeDivision));
          int maxSamples = (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
          int toSample = maxSamples - (gap/2).floor();
          int fromSample = toSample - arr[0] + (gap).floor();
          DraggableGraph.startPositionIdx = fromSample;
          DraggableGraph.endPositionIdx = toSample;

          await processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider, fromSample, toSample);
        } else {
          int maxSamples = (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
          int toSample = (maxSamples + bufferPaddingLeft).toInt();
          toSample = min(maxSamples, toSample);
          int fromSample = (toSample - displayTimeMs * 0.001 * _sampleRate).toInt();
          DraggableGraph.startPositionIdx = fromSample;
          DraggableGraph.endPositionIdx = toSample;
          // processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, fromSample, toSample );
          await processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider, fromSample, toSample);

        }

        // provider.inputListener(Uint8List(0));
      }  
    }
    provider.inputListener(Uint8List(0));

  }
  
  void periodicSerialDataSubscription() {
    periodicTimerSerial?.cancel();
    periodicTimerSerial =Timer.periodic(Duration(milliseconds: 20), (timer){
      bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
      // List<String> listOfPort = Provider.of<PortScanProvider>(context, listen: false).availablePorts;
      serialNativeDataSubscription(Uint8List(0), isAudioListen);
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
  const _AdaptiveArea({required this.child1, required this.child3, required this.child2, required this.notifier});

  final Widget child1;
  final Widget child2;
  final Widget child3;
  final ValueNotifier<List<int>> notifier;

  @override
  State<_AdaptiveArea> createState() => AdaptiveAreaState();
}

class AdaptiveAreaState extends State<_AdaptiveArea> {
  Debouncer debouncerScrollTimeline = Debouncer(milliseconds: 3);
  
  static double horizontalDragX = 0;
  
  static double horizontalDragXFix = 0;

  static String strMaxTime = '';

  static String strMinTime = '';

  static double maxTime = 0;
  @override
  Widget build(BuildContext context) {
    return Consumer<SoftwareConfigProvider>(builder: (context, softwareSetting, snapshot) {
      return SizedBox.expand(
        child: Stack(
          children: [
            widget.child1,
            widget.child2,
            // Padding(
            //   padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
            //   child: widget.child2,
            // ),
            if (GraphTemplate.isPlayerPaused)... {
              getTimeScrubWidget(),
              if (GraphTemplate.isLoadingFile >= 1) ...{
                // strMinTime = "00:00 000";
                Positioned(
                  left: 50,
                  bottom: 110,
                  child: Text(strMinTime,
                      textAlign: TextAlign.left, style: TextStyle(color: Colors.white)),
                ),
                Positioned(
                  right: 50,
                  bottom: 110,
                  child: Container(
                      width: 150,
                      child: Text(strMaxTime,
                          textAlign: TextAlign.right,
                          style: TextStyle(color: Colors.white))),
                )
              }

            },
            softwareSetting.isSettingEnable
                ? Container(
                    // color: Colors.black54.withOpacity(0.9),
                    color: Colors.red,
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
  
  getTimeScrubWidget() {
    horizontalDragXFix = MediaQuery.of(context).size.width - 100 - 20;    
    strMinTime =
        getStrMinTime(horizontalDragX, horizontalDragXFix, maxTime);    
    strMaxTime =
        getStrMinTime(horizontalDragXFix, horizontalDragXFix, maxTime);

    return Positioned(
      left: 0,
      bottom: 140,
      child: GestureDetector(
        onTapDown: (onTapDownDetails) {
          horizontalDragX = onTapDownDetails.localPosition.dx - 50;
          if (horizontalDragX < 0) {
            horizontalDragX = 0;
          }
          if (horizontalDragX >
              MediaQuery.of(context).size.width - 100 - 20) {
            horizontalDragX = MediaQuery.of(context).size.width - 100 - 20;
          }

          strMinTime =
              getStrMinTime(horizontalDragX, horizontalDragXFix, maxTime);
          print("onTapDownDetails : $strMinTime");
          setState(() {});

          debouncerScrollTimeline.run(() {
            if (kIsWeb) {
              // js.context.callMethod(
              //     'setScrollValue', [horizontalDragX, horizontalDragXFix]);
            } else {}
          });
        },
        onHorizontalDragUpdate: (dragUpdateHorizontalDetails) {
          // print("onHorizontalDragUpdate");
          horizontalDragX =
              dragUpdateHorizontalDetails.globalPosition.dx - 50;
          if (horizontalDragX < 0) {
            horizontalDragX = 0;
          }
          if (horizontalDragX >
              MediaQuery.of(context).size.width - 100 - 20) {
            horizontalDragX = MediaQuery.of(context).size.width - 100 - 20;
          }

          strMinTime =
              getStrMinTime(horizontalDragX, horizontalDragXFix, maxTime);
          setState(() {});

          debouncerScrollTimeline.run(() {
            // reload the loaded samples
            // print("debouncerScrollTimeline: $horizontalDragX");
            widget.notifier.value = [horizontalDragX.toInt(), horizontalDragXFix.toInt()];
            // widget.notifier.value = [100, 200];
            // nwbfile_seek_electrical_series(outSamples, outSampleCounts, outConfig, startTimeStamp, endTimeStamp, selectedChannel, channelCount)
            if (kIsWeb) {
              // js.context.callMethod(
              //     'setScrollValue', [horizontalDragX, horizontalDragXFix]);
            } else {}
          });
        },
        child: Container(
            color: const Color(0xFF505050),
            margin: const EdgeInsets.only(left: 50, right: 50),
            width: MediaQuery.of(context).size.width - 100,
            height: 20,
            child: Stack(
              children: [
                Positioned(
                  left: horizontalDragX,
                  child: Container(
                    // color: Colors.green,
                    color: const Color(0xFF808080),
                    width: 20,
                    height: 20,
                  ),
                )
              ],
            )),
      ),
    );    
  }
  
  String getStrMinTime(horizontalDragX, horizontalDragXFix, maxTime) {
    String strMinTime = '';
    // print("minTime");
    // print("horizontalDragX / horizontalDragXFix * maxTime: $horizontalDragX / $horizontalDragXFix * $maxTime}");
    double minTime = horizontalDragX / horizontalDragXFix * maxTime;
    if (minTime > 3600) {
      final lastDecimals =
          (minTime - minTime.floor()).toStringAsFixed(3).replaceFirst("0.", "");
      strMinTime =
          ((minTime / 3600).floor() % (3600 * 24)).toString().padLeft(2, "0") +
              ":" +
              ((minTime / 60).floor() % 3600).toString().padLeft(2, "0") +
              ":" +
              (minTime.floor() % 60).toString().padLeft(2, "0") +
              " " +
              lastDecimals;
    } else {
      final lastDecimals =
          (minTime - minTime.floor()).toStringAsFixed(3).replaceFirst("0.", "");
      strMinTime = ((minTime / 60).floor() % 3600).toString().padLeft(2, "0") +
          ":" +
          (minTime.floor() % 60).toString().padLeft(2, "0") +
          " " +
          lastDecimals;
    }
    // print("minTime");
    // print(strMinTime);
    return strMinTime;
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
