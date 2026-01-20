import 'dart:async';
import 'dart:convert';
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
import 'package:panara_dialogs/panara_dialogs.dart';
import 'package:mic_stream/mic_stream.dart';
// import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:native_add/model/model.dart';
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
import 'package:spikerbox_architecture/provider/custom_slider_provider.dart';
import 'package:spikerbox_architecture/screen/setting_page.dart';
import 'package:spikerbox_architecture/screen/spiker_box_ui.dart';
import 'package:window_manager/window_manager.dart';
import '../provider/provider_export.dart';
import '../widget/widget_export.dart';
import 'graph_page_widget/sound_wave_view.dart';
import 'package:spikerbox_architecture/models/microphone_stream/microphone_stream_check.dart';

import 'package:another_xlider/another_xlider.dart';
import 'package:file_picker/file_picker.dart';

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

class _GraphTemplateState extends State<GraphTemplate> {
  String serialUsageType = "";
  List<double> bufferPos = [0, 0];
  var seekElectricalSeriesWebCompleter = Completer<Map<String, dynamic>>(); 

  var envelopeSizes = [];
  List<int> skipCounts = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512];
  List<int> arrCounts = [ 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048 ];

  List<String> listOfDevices = ["PLANTSS;", "MUSCLESS;", "HEARTSS;", "HBLEOSB;", "HUMANSB;", "MSBPCDC;", "NSBPCDC;", "NRNSBPRO;", "HHIBOX;"];  
  List<String> _availablePorts = [];
  LocalPlugin localPlugin = LocalPlugin();
  MicrophoneUtil microphoneUtil = MicrophoneUtil();
  final double _sliderValue = 25;
  double startValue = 0;
  double endValue = 22000;
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

  late MessageIdentifier _messageIdentifier;

  /// For testing keeping track of packets sent to C code
  static int packetId = 0;

  // For audio data

  static const int _sampleGeneratedCount = 1000;
  static const int timeMs = _sampleGeneratedCount * 1000 ~/ dummySamplingRate;
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
    _portCheckTimer?.cancel();
    _portCheckTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (forceSerialDisconnect) return;
      if (isOpeningFile) return;
      if (_isDataIdentified) return;

      // print("START PORT CHECK");
      int baudRate = context.read<ConstantProvider>().getBaudRate();
      _serialUtil.getAvailablePorts(baudRate, serialErrorCallback);
      allDevices.clear();

      List<String> filteredPorts;
      if (kIsWeb) {
        filteredPorts = _serialUtil.availablePorts;
      } else if (Platform.isMacOS) {
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
          isSerialDeviceFound = true;
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

    deviceListStream = connectDeviceList();

    Future.delayed(Duration(milliseconds: 1000), () async {
      GraphGainProvider graphGainProvider = Provider.of<GraphGainProvider>(context, listen: false);
      if (_graphGainProviderListener != null) {
        graphGainProvider.removeListener(_graphGainProviderListener!);
      }
      _graphGainProviderListener = () {
        // if (selectedBoard?.uniqueName == "HUMANSB;") {
        //   if (graphGainProvider.stepGain > 0) {
        //     String selectedCommand = "gainon:${graphGainProvider.curChannelIdx};";
        //     print("SELECTED COMMAND: $selectedCommand");
        //     Uint8List commandBytes = Uint8List.fromList(utf8.encode(selectedCommand));
        //     _serialUtil.writeToPort(bytesMessage: commandBytes, address: _availablePorts.last);
        //   } else if (graphGainProvider.stepGain < 0) {
        //     String selectedCommand = "gainon:${graphGainProvider.curChannelIdx};";
        //     print("SELECTED COMMAND: $selectedCommand");
        //     Uint8List commandBytes = Uint8List.fromList(utf8.encode(selectedCommand));
        //     _serialUtil.writeToPort(bytesMessage: commandBytes, address: _availablePorts.last);
            
        //   } else {
        //     String selectedCommand = "gainoff:${graphGainProvider.curChannelIdx};";
        //     print("SELECTED COMMAND: $selectedCommand");
        //     Uint8List commandBytes = Uint8List.fromList(utf8.encode(selectedCommand));
        //     _serialUtil.writeToPort(bytesMessage: commandBytes, address: _availablePorts.last);

        //   }
        //   return;
        // }
      };
      graphGainProvider.addListener(_graphGainProviderListener!);

      GraphDataProvider graphDataProvider = Provider.of<GraphDataProvider>(context, listen: false);
      // Remove old listener if it exists
      if (_graphDataProviderListener != null) {
        graphDataProvider.removeListener(_graphDataProviderListener!);
      }
      _graphDataProviderListener = () {
        print("GraphDataProvider LISTENER : rewind ${graphDataProvider.isRewind} | forward ${graphDataProvider.isForward}");
        if (graphDataProvider.isRewind) {
          if (!isOpeningFile) return;
          _serialUtil.isOpeningFile = false;

          graphDataProvider.isRewind = false;
          AdaptiveAreaState.maxTime = loadedMaxSamples / _sampleRate;
          double scrubMaxWidth = MediaQuery.of(context).size.width - 100 - 20;
          AdaptiveAreaState.horizontalDragX = scrubMaxWidth * 0;
          scrubNotifier.value = [ 0, scrubMaxWidth];
          streamScrubBuilderController.add(Random().nextInt(100000));
          Future.delayed(Duration(milliseconds: 100), () async {
            callbackPlayButton(true);
          });
          setState(() {});
        } else 
        if (graphDataProvider.isForward) {
          graphDataProvider.isForward = false;
          Provider.of<GraphResumePlayProvider>(context, listen: false).setGraphResumePlay(true);
          GraphTemplate.isPlayerPaused = false;
          GraphTemplate.isLoadingFile = 0;
          try{
            periodicTimerSerial?.cancel();
          }catch(err) {
            print("ERR: $err");
          }          
          // Reset processing position indices to prevent showing more than 10 seconds
          ProcessingUtil.positionIndex = 0;
          ProcessingUtil.fromSample = 0;
          ProcessingUtil.toSample = 0;
          
          // Reset DraggableGraph position indices
          int maxSamples = (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
          int maxDisplaySamples = (displayTimeMs * 0.001 * _sampleRate).floor();
          DraggableGraph.startPositionIdx = maxSamples - maxDisplaySamples;
          DraggableGraph.endPositionIdx = maxSamples;

          // Clear event markers
          ProcessingUtil.eventLabels.clear();
          ProcessingUtil.eventPosition.clear();
          ProcessingUtil.currentEventMarkers = 0;

          // Reset total sample count
          totalSampleCount = 0;
          
          if (!kIsWeb) {
            listenToMicrophone(1, graphDataProvider);
          } else {
            forceSerialDisconnect = false;
            GraphTemplate.isLoadingFile = 0;
            if (isOpeningFile) {
              print("CANCELING PERIODIC TIMER SERIAL");

              try{
                _serialUtil.closePort();
                Future.delayed(Duration(milliseconds: 1500), () {
                  if (context.mounted) {
                    _availablePorts.clear();
                  }
                });            
              }catch(err) {
                print("ERR: $err");
              }
              listenToMicrophone(1, graphDataProvider);
            }
          }
          isOpeningFile = false;
          setState(() {});
        }
      };
      graphDataProvider.addListener(_graphDataProviderListener!);

    });

  // Remove old listener if it exists
    if (_scrubNotifierListener != null) {
      scrubNotifier.removeListener(_scrubNotifierListener!);
    }
    _scrubNotifierListener = () async {
      print("SECTION ScrubNotifier: $timeMs");
      // print("scrubNotifier");
      timerPlaybackLoadedStartIndex = 0;
      timerPlaybackLoadedEndIndex = 0;

      List<double> timeScrub = scrubNotifier.value;
      if (timeScrub.isEmpty) return;
      double percentage = timeScrub[0] / timeScrub[1];

      // nwbfile_seek_electrical_series(outSamples, outSampleCounts, outConfig, startTimeStamp, endTimeStamp, selectedChannel, channelCount)
      Int16List arrSamples = Int16List(1);
      loadedMaxSamples = loadedConfig[5].toDouble();
      int sampleRateConfig = loadedConfig[0].round();
      double maxScreenSamples = ProcessingUtil.MAX_DISPLAY_SECONDS * sampleRateConfig;
      double arrSamplesLength = maxScreenSamples;
      double startSeekSample = 0;

      double currentSamples = percentage * loadedMaxSamples;
      if (currentSamples < maxScreenSamples) {
        startSeekSample = 0;
        arrSamplesLength = currentSamples;
      } else 
      if (currentSamples >= maxScreenSamples) {
        startSeekSample = currentSamples - maxScreenSamples;
        arrSamplesLength = maxScreenSamples;
      }

      // double arrSamplesLength = maxSamples.toDouble();
      arrSamples = Int16List(arrSamplesLength.floor() * widget.channelCount);

      Int32List arrSampleCount = Int32List(widget.channelCount);

      // double percentage = 0.1;
      // double startSeekSample = (arrSamplesLength * percentage);
      // double startSeekSample = loadedMaxSamples * percentage;
      // double endSeekSample = arrSamplesLength; // (arrSamplesLength - startSeekSample).floor()
      // double endSeekSample = min(startSeekSample + arrSamplesLength, loadedMaxSamples.toDouble()); // (arrSamplesLength - startSeekSample).floor()
      double endSeekSample = currentSamples; 
      startPlaybackSeekSampleIdx = currentSamples;
      
      // print("START SEEK SAMPLE: $startSeekSample | END SEEK SAMPLE: $endSeekSample | arrSamplesLength: $arrSamplesLength | loadedMaxSamples: $loadedMaxSamples");
      if (startSeekSample + arrSamplesLength > loadedMaxSamples) {
        return;
      } else {
      }
      startSeekSampleIdx = startSeekSample;
      endSeekSampleIdx = endSeekSample;
      print("START SEEK SAMPLE IDX: $startSeekSample $endSeekSampleIdx");
      ProcessingUtil.fromDrawingIdx = startSeekSampleIdx.floor();
      ProcessingUtil.toDrawingIdx = endSeekSampleIdx.floor();

      if (endSeekSample == startSeekSample && endSeekSample == 0) {
        endSeekSample = 1;  
      }
      // if (seekFlag != null && !seekFlag) {
      //   print("SEEK FAILED");
      //   return;
      // }

      if (!kIsWeb) {
        bool? seekFlag = await GraphTemplate.nwbFileUtil?.seekElectricalSeries(currentLoadedFilePath, arrSamples, arrSampleCount, loadedConfig, (startSeekSample).floor(), endSeekSample.floor(), 0, widget.channelCount - 1);
        print("SCRUB NOTIFIER: WIDGET CHANNEL COUNT: $widget.channelCount | Percentage: $percentage @@@ Config: $loadedConfig ||| scrubNotifier: ${timeScrub} ${(arrSamplesLength * percentage).floor()}, ${(arrSamplesLength - startSeekSample).floor()}");
      } else {
        seekElectricalSeriesWebCompleter = Completer<Map<String, dynamic>>(); 
        await GraphTemplate.nwbFileUtil?.seekElectricalSeriesWeb(currentLoadedFilePath, arrSamples, arrSampleCount, loadedConfig, (startSeekSample).floor(), endSeekSample.floor(), 0, widget.channelCount - 1);
        Map<String, dynamic> map = await seekElectricalSeriesWebCompleter.future;
        arrSamples = map['arrSamples'];
        arrSampleCount = map['arrSampleCount'];
        loadedConfig = map['loadedConfig'];
      }

      int combinedIdx = 0;
      int totalChannelCount = loadedConfig[1];
      loadedArrSamples.clear();
      loadedArrChannelCount = (Int32List(widget.channelCount));
      print("Scrub : ${widget.channelCount} | arrSamples: ${arrSamples.length} | arrSampleCount: ${arrSampleCount} | combinedIdx: $combinedIdx");
      for (int i = 0; i < widget.channelCount; i++) {
        // double initialSampleCount = arrSampleCount[i].floor() / totalChannelCount;
        // double initialSampleCount = arrSampleCount[0].toDouble();
        double initialSampleCount = arrSampleCount[i].toDouble();
        if (arrSamples.length >= combinedIdx + initialSampleCount) {
          // print("LOADED ARR SAMPLES INTERUPTED: $initialSampleCount + $combinedIdx ?? ${arrSamples.length}");
          loadedArrSamples.add(Int16List(initialSampleCount.floor()));
          loadedArrSamples[i].setAll(0, arrSamples.sublist(combinedIdx, combinedIdx + initialSampleCount.floor()));
          // loadedArrChannelCount.fillRange(0, totalChannelCount, initialSampleCount.floor());
          loadedArrChannelCount[i] = initialSampleCount.floor();
          combinedIdx += initialSampleCount.floor();
        }
      }
      loadedConfig[7] = MediaQuery.of(context).size.width.toInt();
      processingUtil.initWithConfig(loadedConfig);
      

      GraphTemplate.isLoadingFile = 1;
      GraphTemplate.isPlayerPaused = true;


      // Future.delayed(Duration(milliseconds: 100), () async{
      //   context.read<GraphDataProvider>().addListener(() {
      //     print("GraphDataProvider LISTENER");
      //     if (context.read<GraphDataProvider>().isRewind) {
      //       context.read<GraphDataProvider>().resetGraphBuffer();
      //       // startOpeningFile();
      //     } 
      //   });
      // });

    };
    scrubNotifier.addListener(_scrubNotifierListener!);
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
    processingUtil.postChannelCountStream = processingUtil.postChannelCountController.stream.asBroadcastStream();

    print("postChannelCountStream: ${processingUtil.postChannelCountStream}");
    processingUtil.postChannelCountStream?.listen((channelCount) {
      print("EXPANSION BOARD CHANNEL COUNT: $channelCount");
      widget.channelCount = channelCount;
      context.read<ConstantProvider>().setChannelCount(channelCount);
      
      // Device is serial 
      context.read<ChannelColorProvider>().setSerialChannelCount(channelCount);
      ProcessingUtil.initializeDevice.value = ( (ProcessingUtil.initializeDevice.value * 10) + 2 + Random().nextInt(10) + channelCount).floor();
    });
    GraphTemplate.processingUtil = processingUtil;
    GraphTemplate.nwbFileUtil = createNwbFileUtil();
    if (GraphTemplate.nwbFileUtil != null) {
      GraphTemplate.nwbFileUtil!.onStartOpeningFileWebCallback = startOpeningFileWebCallback;
      GraphTemplate.nwbFileUtil!.onStartOpeningFileWebCallbackPlayback = startOpeningFileWebCallbackPlayback;
    } else {
      print("ERROR: GraphTemplate.nwbFileUtil is null");
    }

    final provider = Provider.of<GraphDataProvider>(context, listen: false);
    // Initialize stream and set provider
    _graphStream = _graphStreamController.stream.asBroadcastStream();
    provider.setStreamOfData(_graphStream);

    streamScrubBuilder = streamScrubBuilderController.stream.asBroadcastStream();
    streamValueBuilder = streamValueBuilderController.stream.asBroadcastStream();

    SchedulerBinding.instance.addPostFrameCallback((timeStamp) async {
      setSampleRate();
    });
    if (!kIsWeb) {
      _startPortCheck();
    }

    listenToMicrophone(1, provider);

    filterBaseSettingsModel = FilterSetup(filterConfiguration: FilterConfiguration(cutOffFrequency: 1000, sampleRate: 10000), filterType: FilterType.highPassFilter, channelCount: channelCountBuffer, isFilterOn: false);
    _sampleData = GenerateSampleData.sineWaveUint14(samplingRate: dummySamplingRate, frequencies: [50, 1000], samplesGenerated: _sampleGeneratedCount).buffer.asUint8List();

    _dummyDataTimer?.cancel();
    _dummyDataTimer = Timer.periodic(const Duration(milliseconds: timeMs), (timer) {
      bool dummyDataStatus = context.read<DataStatusProvider>().isSampleDataOn;
      if (dummyDataStatus) {
        _preprocessingBuffer.addBytes(_sampleData);
      }
    });

    localPlugin.spawnHelperIsolate().then(
      (value) {
        localPlugin.postChannelCountStream?.listen((channelCount) {
          print("EXPANSION BOARD CHANNEL COUNT: $channelCount");
          widget.channelCount = channelCount;
          context.read<ConstantProvider>().setChannelCount(channelCount);
          
          // Device is serial 
          context.read<ChannelColorProvider>().setSerialChannelCount(channelCount);
          ProcessingUtil.initializeDevice.value = (ProcessingUtil.initializeDevice.value * 10) + 2 + Random().nextInt(10) + channelCount;
        });
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


    initMessageIdentifier();
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
          if (SoundWaveView.dragDetails != null) {
            print("DRAG DETAILS!!");
            double prevStartElementIdx = screenPositionToElementPosition(SoundWaveView.dragDetails!.position.dx, _sampleRate, ProcessingUtil.positionIndex, 
              TimeCalculateWidget.prevDisplayTimeMsLabel *0.001, TimeCalculateWidget.prevWidthOfScale, MediaQuery.of(context).size.width, bufferPos);
            double startElementIdx = screenPositionToElementPosition(SoundWaveView.dragDetails!.position.dx, _sampleRate, ProcessingUtil.positionIndex, 
              TimeCalculateWidget.displayTimeMsLabel *0.001, TimeCalculateWidget.widthOfScale, MediaQuery.of(context).size.width, bufferPos);
            print("DIFFERENCES = $prevStartElementIdx - $startElementIdx = ${prevStartElementIdx - startElementIdx} | ${ProcessingUtil.positionIndex}");
            // print("LABELS: ${DraggableGraph.eventMarkersPosition} ${DraggableGraph.eventMarkersLabels} ||| ${ProcessingUtil.eventLabels.sublist(0, ProcessingUtil.currentEventMarkers)} - Sublist: ${ProcessingUtil.eventPosition.sublist(0, ProcessingUtil.currentEventMarkers)}");
// main.dart.js:25928 DIFFERENCES = NaN - 524989.0625 = NaN | 0            
            if (prevStartElementIdx.isNaN) {
              bufferPaddingLeft = bufferPaddingLeft;
            } else {
              bufferPaddingLeft = bufferPaddingLeft - (prevStartElementIdx - startElementIdx);
            }
            if (displayTimeMs == 10000) {
              bufferPaddingLeft = 0;
            }
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
    print("GraphTemplate dispose: cleaning up resources...");
    
    // Cancel all timers
    _portCheckTimer?.cancel();
    _dummyDataTimer?.cancel();
    periodicTimerSerial?.cancel();
    timerPlaybackLoadedFile?.cancel();
    
    // Remove listeners
    if (_graphDataProviderListener != null) {
      try {
        final graphDataProvider = Provider.of<GraphDataProvider>(context, listen: false);
        graphDataProvider.removeListener(_graphDataProviderListener!);
      } catch (e) {
        print("Error removing graphDataProvider listener: $e");
      }
      _graphDataProviderListener = null;
    }
    
    if (_scrubNotifierListener != null) {
      try {
        scrubNotifier.removeListener(_scrubNotifierListener!);
      } catch (e) {
        print("Error removing scrubNotifier listener: $e");
      }
      _scrubNotifierListener = null;
    }
    
    // Remove mic listener
    try {
      microphoneUtil.micStream.removeListener(micListener);
      if (!kIsWeb) {
        print("microphoneUtil.micStatus?.cancel()");
        microphoneUtil.micStatus?.cancel();
      }
    } catch (e) {
      print("Error removing micListener: $e");
    }
    
    // Cancel subscriptions
    serialDataSubscription?.cancel();
    microphoneSubscription?.cancel();
    
    // Dispose processing util
    try {
      (processingUtil as ProcessingUtilImpl).dispose();
    } catch (e) {
      print("Error disposing processingUtil: $e");
    }
    GraphTemplate.processingUtil = null;
    
    // Close stream controllers
    streamScrubBuilderController.close();
    
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
  Widget build(BuildContext widgetContext) {
    bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
    return Scaffold(
      backgroundColor: SoftwareColors.kBackGroundColor,
      body: StreamBuilder<int>(
        stream: streamScrubBuilder,
        builder: (context, snapshot) {
          // print("streamScrubBuilder: ${snapshot.data} -- $startValue, $endValue");
          return _AdaptiveArea(
              recordingNotifier: recordingNotifier,
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
                  ]),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 500,
                      ),
                      child: Column(
                        children: [
                          SizedBox(height: 20),
                          // if (!isAudioListen) ... {
                          if (1==1) ... {
                            _predefinedFilterSettings(),
                          },
                          SizedBox(height: 20),
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
              child4: !kIsWeb && Platform.isAndroid && isThresholdingButton ? Positioned(
                left: 10,
                top: 80,
                child: Row(
                  children: generateThresholdSlider(false),
                ),
              ): SizedBox(),
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
                              isRecording == 1 ? 
                              SizedBox() 
                              : 
                              SpikerBoxButton(
                                  onTapButton: () async {
                                    context.read<SoftwareConfigProvider>().settingStatus(true);
                                  },
                                  iconData: Icons.settings),
                              const SizedBox(
                                width: 10,
                              ),

                              serialWebButton(),
                              // SpikerBoxButton(
                              //     onTapButton: () async {}, iconData: Icons.graphic_eq),
                              // const SizedBox(
                              //   width: 10,
                              // ),
                              isRecording == 1 ? 
                              SizedBox() 
                              : 
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
                                iconColor: isThresholdingButton? Colors.yellow : Colors.white,
                                iconData: Icons.graphic_eq_outlined,
                              ),
                              const SizedBox(
                                width: 20,
                              ),
                              if (isThresholdingButton) ... {
                  
                                ...generateThresholdSlider(true),
                                
                                
                                // Container(
                                //   width:50,
                                //   height:30,
                                //   child: TextField(
                                //     controller: thresholdValueController,
                                //   )
                                // )
                              },
                              
                              // if (!isThresholdingButton) ... {
                              //   SpikerBoxButton(
                              //     onTapButton: () {
                              //       isFftButton = !isFftButton;
                              //       if (isFftButton) {
                              //         context.read<FftStatusProvider>().setFftVisibility(true);
                              //       } else {
                              //         context.read<FftStatusProvider>().setFftVisibility(false);
                              //       }
                  
                              //       setState((){});
                              //     },
                              //     iconColor: isFftButton? Colors.yellow : Colors.black,
                              //     iconData: Icons.abc,
                              //   ),
                              // },
                              const SizedBox(
                                width: 10,
                              ),
                              // if (!forceSerialDisconnect) ... {
                              //   SpikerBoxButton(onTapButton: () {
                              //     forceSerialDisconnect = !forceSerialDisconnect;
                              //   }, iconData: Icons.usb),
                              // },
                              StreamBuilder<List<ComDataWithBoard>>(
                                  stream: deviceListStream,
                                  builder: (context, snapshot) {
                                    // print("snapshot.hasData: ${snapshot.hasData}");
                                    if (snapshot.hasData) {
                                    print("snapshot.data: ${snapshot.data}");
                                      listOfBoard = snapshot.data!;
                                      if (listOfBoard?.length == 0) {
                                        return SpikerBoxButton(onTapButton: () async{
                                          forceSerialDisconnect = true;
                                          initMessageIdentifier();                                          

                                          await Future.delayed(Duration(milliseconds: 1000));
                                          
                                          int baudRate = context.read<ConstantProvider>().getBaudRate();
                                          await _serialUtil.getAvailablePorts(baudRate, serialErrorCallback);
                                          allDevices.clear();

                                          List<String> filteredPorts;
                                          if (kIsWeb) {
                                            filteredPorts = _serialUtil.availablePorts;
                                          } else if (Platform.isMacOS) {
                                            filteredPorts = _serialUtil.availablePorts.where((port) => port.contains('usbmodem') || port.contains('usbserial')).toList();
                                          } else {
                                            filteredPorts = _serialUtil.availablePorts;
                                          }

                                          bool isComMatch = areListsEqual(_availablePorts, filteredPorts);

                                          _availablePorts = filteredPorts;
                                          
                                          context.read<DataStatusProvider>().setMicrophoneDataStatus(_availablePorts.isEmpty);
                                          print("isDeviceConnect : $isDeviceConnect -- ${_availablePorts.isEmpty} -- ${context.read<DataStatusProvider>().isMicrophoneData} -- forceSerialDisconnect: $forceSerialDisconnect ${listOfBoard?.length} isComMatch: $isComMatch");

                                          // if (!isComMatch) {
                                            Provider.of<PortScanProvider>(context, listen: false).setPortScanList(_availablePorts);
                                            Provider.of<ConstantProvider>(context, listen: false).setBaudRate(baudRate);
                                            allDevices = context.read<SerialDataProvider>().getAllPortDetail;
                                            if (isDeviceConnect) {
                                              isSerialDeviceFound = true;
                                              await portListOnConnect();
                                            }
                                          // }
                                          forceSerialDisconnect = false;
          
                                        }, iconData: Icons.usb);
                                      }

                                      return SizedBox(
                                        height: 50,
                                        child: ListView.builder(
                                            padding: EdgeInsets.zero,
                                            scrollDirection: Axis.horizontal,
                                            shrinkWrap: true,
                                            itemCount: listOfBoard?.length,
                                            itemBuilder: (context, index) {
                                              return SpikerBoxButton(onTapButton: () {
                                                print("DISCONNECT USB");
                                                forceSerialDisconnect = !forceSerialDisconnect;
                                                _serialUtil.closePort();
                                                Future.delayed(Duration(milliseconds: 1500), () {
                                                  if (context.mounted) {
                                                    _availablePorts.clear();
                                                    context.read<DataStatusProvider>().setMicrophoneDataStatus(_availablePorts.isEmpty);
                                                    final provider = Provider.of<GraphDataProvider>(context, listen: false);
                                                    listenToMicrophone(1, provider);
                                                  }
                                                  // final provider = Provider.of<GraphDataProvider>(context, listen: false);
                                                });
                                                                
                                              }, iconData: Icons.usb);
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
                              isOpeningFile ? SizedBox() : 
                              SpikerBoxButton(
                                onTapButton: () async {
                                  print("STATUS RECORDING: $isRecording");
                                  if (isRecording == 0) {
                                    print("!!!INIT NWB FILE, $_sampleRate, ${_channelCount.length}");
                                    
                                    bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
                                    visibleSignalsList = context.read<ChannelColorProvider>().getVisibleChannel();
                                    visibleChannelCount = context.read<ChannelColorProvider>().getVisibleChannelCount();

                                    if (kIsWeb) {
                                      await GraphTemplate.nwbFileUtil?.recordNewFileLocation();
                                      int counterTimerCancel = 0;
                                      Timer.periodic(Duration(seconds: 1), (timer) async {
                                        // counterTimerCancel++;
                                        print("GraphTemplate.nwbFileUtil?.recordedNwbFilePath: ${GraphTemplate.nwbFileUtil?.recordedNwbFilePath}");
                                        String strTemp = GraphTemplate.nwbFileUtil?.recordedNwbFilePath ?? "";
                                        if (strTemp.length! > 3) {
                                          timer.cancel();
                                          if (isAudioListen) {
                                            recordedFilePath = await GraphTemplate.nwbFileUtil?.processingInit(_sampleRate, widget.channelCount, "Audio|||", "SpikeRecorder Systems", visibleSignalsList, visibleChannelCount);
                                          } else {
                                            recordedFilePath = await GraphTemplate.nwbFileUtil?.processingInit(_sampleRate, widget.channelCount, "SpikeRecorder Device|||", "SpikeRecorder Systems", visibleSignalsList, visibleChannelCount);
                                          }
                                          bool isPlay = true;
                                          Provider.of<GraphResumePlayProvider>(context, listen: false).setGraphResumePlay(isPlay);
                                          _toPauseGraph = isPlay;
                                          GraphTemplate.isPlayerPaused = !isPlay;
                                          _pendingPlayback = false;
                                          
                                          Future.delayed(Duration(milliseconds: 1000), () {
                                            isRecording = 1;
                                            context.read<ChannelColorProvider>().setIsRecording(1);

                                            recordingStartTime = DateTime.now().millisecondsSinceEpoch;

                                            recordingNotifier.value = [recordingStartTime, recordingStartTime];
                                            setState((){});
                                          });
                                        }else 
                                        if (GraphTemplate.nwbFileUtil?.recordedNwbFilePath == "--"){
                                          GraphTemplate.nwbFileUtil?.recordedNwbFilePath = "";
                                          print("NWB FILE PATH");
                                          counterTimerCancel = 0;
                                          isOpeningFile = false;
                                          timer.cancel();
                                        }
                                      });
                                    } else {
                                      if (isAudioListen) {
                                        recordedFilePath = await GraphTemplate.nwbFileUtil?.processingInit(_sampleRate, widget.channelCount, "Audio|||", "SpikeRecorder Systems", visibleSignalsList, visibleChannelCount);
                                      } else {
                                        recordedFilePath = await GraphTemplate.nwbFileUtil?.processingInit(_sampleRate, widget.channelCount, "SpikeRecorder Device|||", "SpikeRecorder Systems", visibleSignalsList, visibleChannelCount);
                                      }
                                      Future.delayed(Duration(milliseconds: 1000), () {
                                        isRecording = 1;
                                        context.read<ChannelColorProvider>().setIsRecording(1);
                                        recordingStartTime = DateTime.now().millisecondsSinceEpoch;

                                        recordingNotifier.value = [recordingStartTime, recordingStartTime];
                                        setState((){});

                                      });
                                    }
                                    // isRecording = 1;
                                  } else {
                                    resetRecordingState(widgetContext);

                                    setState((){});
                                  }
                                },
                                iconData: Icons.fiber_manual_record,
                                iconColor: isRecording == 1 ? Colors.red : Colors.white,
                              ),
                              const SizedBox(
                                width: 10,
                              ),
                              if (isRecording != 1) ... {
                                SpikerBoxButton(onTapButton: () async {
                                  if (kIsWeb) {
                                    // print("START OPENING FILE WEB");
                                    startOpeningFileWeb("", 0, 1);
                                    // startOpeningFile(result.files.single.path!);
                                  } else {
                                    FilePickerResult? result = await FilePicker.platform.pickFiles();
                                    if (result != null) {
                                      startOpeningFile(result.files.single.path!);
                                    }
                                  }
                                }, iconData: Icons.menu)
                              },
                            ],
                          )
                        ],
                      ),
                      isRecording != 0 ? SizedBox() : BottomButtons(
                        pauseButton: (bool isPlay) async {
                          if (!isOpeningFile) {
                            Provider.of<GraphResumePlayProvider>(context, listen: false).setGraphResumePlay(isPlay);
                            _toPauseGraph = isPlay;
                            GraphTemplate.isPlayerPaused = !isPlay;
                            _pendingPlayback = false;
                             setState(() {});
                          } else {
                            callbackPlayButton(isPlay);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ));
        }
      ),
      floatingActionButton: null,
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
    try {
      DataStatusProvider dataStatus = context.read<DataStatusProvider>();
      List<String> listOfPort = Provider.of<PortScanProvider>(context, listen: false).availablePorts;
      int baudRate = context.read<ConstantProvider>().getBaudRate();
      print("portListOnConnect listOfPort: $listOfPort");
      if (listOfPort.isEmpty) {
        return;
      }
      getData = await _serialUtil.openPortToListen(listOfPort.last, baudRate);
      
      // Only proceed if connection was successful
      if (getData == null) {
        print("Failed to connect to port: ${listOfPort.last}");
        dataStatus.setDeviceDataStatus(false);
        return;
      }
      
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

    if (Platform.isAndroid) {
      deviceStatusStreamSubscription?.cancel();
      deviceStatusStreamSubscription = _serialUtil.deviceStatusStreamListener().listen((event) {
        print("DEVICE STATUS STREAM: $event");
        if (event == "android.hardware.usb.action.USB_DEVICE_DETACHED") {
          forceSerialDisconnect = true;
          print("SERIAL PORT ERROR -- DISCONNECTED");
          serialDataSubscription?.cancel();
          deviceStatusStreamSubscription?.cancel();
          _serialUtil.closePort();
          Future.delayed(Duration(milliseconds: 2500), () {
            forceSerialDisconnect = false;
            _isSerialWebButtonEnabled = false;
            isDeviceConnect = false;
            isDeviceSelected = false;
            _isDataIdentified = false;
            streamScrubBuilderController.add(Random().nextInt(100000));
            listenToMicrophone(1, provider);                   
          });
        }
      });
    }

    serialDataSubscription?.cancel();
    serialDataSubscription = getData?.listen((event) async {
      isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
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
            Future.delayed(Duration(milliseconds:100), () {
              Uint8List commandBytes = Uint8List.fromList(utf8.encode("board:;"));
              _serialUtil.writeToPort(bytesMessage: commandBytes, address: _availablePorts.last);
            });
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
                // DEBUG STEVE
                // return;            

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
              // DEBUG STEVE
            // return;            

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
        forceSerialDisconnect = true;
        print("SERIAL PORT ERROR -- DISCONNECTED");
        _serialUtil.closePort();
        Future.delayed(Duration(milliseconds: 2500), () {
          forceSerialDisconnect = false;
          listenToMicrophone(1, provider);
        });

        // processingUtil.init();
        // processingUtil.initializeMicrophone(1, _sampleRate, MediaQuery.of(context).size.width);
      // }
    });
    portName = listOfPort.last;
    } catch (e) {
      print("Error in portListOnConnect: $e");
      DataStatusProvider dataStatus = context.read<DataStatusProvider>();
      dataStatus.setDeviceDataStatus(false);
      // Clean up on error
      _serialUtil.closePort();
    }
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
  StreamSubscription<String?>? deviceStatusStreamSubscription;
  
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

  void listenToMicrophone(channelCount, provider) async {
    print("listenToMicrophone");
    stopCurrentPlaying();

    
        
    // Prevent multiple simultaneous calls
    if (_isListeningToMicrophone) {
      print("listenToMicrophone already in progress, waiting for completion...");
      if (_listenToMicrophoneCompleter != null) {
        await _listenToMicrophoneCompleter!.future;
      }
      return;
    }
    
    localPlugin.currentExpansionBoardString = "";
    visibleSignalsList = [1];
    visibleChannelCount = 1;
    
    _isListeningToMicrophone = true;
    _listenToMicrophoneCompleter = Completer<void>();
    
    try {
      if (provider == null) {
        provider = Provider.of<GraphDataProvider>(context, listen: false);      
      }
      isDeviceConnect = true;
      _isSerialWebButtonEnabled = false;
      isDeviceSelected = false;
      _isDataIdentified = false;
      deviceChannelCount = channelCount;
      GraphTemplate.isLoadingFile = 0;
      foundDevices = "";

      try{
        widget.channelCount = channelCount;
        Provider.of<ConstantProvider>(context, listen: false).setChannelCount(channelCount);
        Provider.of<SampleRateProvider>(context, listen: false).setSampleRate(microphoneUtil.sampleRate.floor());

        microphoneUtil.micStream.removeListener(micListener);
        microphoneUtil.micStream = ValueNotifier(Uint8List(0));
        context.read<DataStatusProvider>().setMicrophoneDataStatus(true);
        print("LISTEN TO MICROPHONE setMicrophoneDataStatus");

      }catch(err){
        print("er remove listener");
        print(err);
      }

      await Future.delayed(const Duration(microseconds: 10));
      
      print("_messageIdentifier.messageState");
      print(_messageIdentifier.messageState);
      // Initialize both utils


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

      // Clear envelopeSizes to prevent accumulation
      envelopeSizes.clear();
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

      print("listenToMicrophone5");
      microphoneUtil.micStream.addListener(micListener);    
      isDeviceConnect = true;
      isDeviceSelected = false;
      ProcessingUtil.initializeDevice.value = 0;
      
      _listenToMicrophoneCompleter!.complete();
    } catch (error) {
      print("Error in listenToMicrophone: $error");
      if (_listenToMicrophoneCompleter != null && !_listenToMicrophoneCompleter!.isCompleted) {
        _listenToMicrophoneCompleter!.completeError(error);
      }
    } finally {
      _isListeningToMicrophone = false;
      _listenToMicrophoneCompleter = null;
      _isSerialWebButtonEnabled = false;
      setState(() => {});
    }
  }

  List<int> arr = [];
  
  int thresholdSliderValue = 1;
  
  double FFT_WIDGET_HEIGHT = 0.3;
  
  int FFT_30HZ_LENGTH = 32;
  int FFT_WINDOW_TIME_LENGTH = 4;
  /*
  0: not recording
  1: init finish - start recording
  2: recording finished
   */
  int isRecording = 0;
  
  Timer? timerPlaybackLoadedFile;
  double timerPlaybackLoadedStartIndex = 0;
  double timerPlaybackLoadedEndIndex = 0;
  double loadedMaxSamples = 0;
  Int32List loadedConfig = Int32List(10);
  List<Int16List> loadedArrSamples = [];
  Int32List loadedArrChannelCount = Int32List(1);

  double startSeekSampleIdx = 0;
  double endSeekSampleIdx = 0;
  
  ValueNotifier<List<double>> scrubNotifier = ValueNotifier([]);
  ValueNotifier<List<int>> recordingNotifier = ValueNotifier([0,0]);

  SoLoud.SoLoud? soloud;
  List<SoLoud.AudioSource?> loadedFileStreams = [];
  
  List<SoLoud.SoundHandle?> loadedSoundHandles = [];
  
  bool isOpeningFile = false;
  
  Stream<Uint8List>? getData;
  
  Timer? periodicTimerSerial;
  Timer? _portCheckTimer;
  Timer? _dummyDataTimer;
  
  // Listener references for cleanup
  VoidCallback? _graphDataProviderListener;
  VoidCallback? _graphGainProviderListener;
  VoidCallback? _scrubNotifierListener;
  
  // Guard to prevent multiple simultaneous listenToMicrophone calls
  bool _isListeningToMicrophone = false;
  Completer<void>? _listenToMicrophoneCompleter;
  
  String currentLoadedFilePath = "";
  
  // Track pending playback for web async callback
  bool _pendingPlayback = false;
  double _pendingPlaybackStartIdx = 0;
  
  double sampleDivider = 0;
  
  double startPlaybackSeekSampleIdx = 0;
  
  final StreamController<int> streamScrubBuilderController = StreamController();  
  Stream<int>? streamScrubBuilder;
  final StreamController<int> streamValueBuilderController = StreamController();  
  Stream<int>? streamValueBuilder;
  
  int recordingStartTime = 0;
  
  String? recordedFilePath = "";
  
  bool forceSerialDisconnect = false;
  
  bool isSerialDeviceFound = false;
  
  Stream<List<ComDataWithBoard>>? deviceListStream;
  
  
  

  void micListener(){
    // print("miCLISTENER DATA | TIME: ${DateTime.now().millisecondsSinceEpoch} |||| ${microphoneUtil.micStream.value.sublist(0,10)}");
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
        // List<Int16List> tempData = processingUtil.processMicrophoneData(loadedArrSamples.sublist(0, loadedArrChannelCount[0]).buffer.asUint8List());
        // loadedArrSamples[0].fillRange(0, loadedArrSamples[0].length, 5000);
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
                if (!kIsWeb) {
                  GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 1, 0);
                }
                recordingNotifier.value = [recordingStartTime, DateTime.now().millisecondsSinceEpoch];

                // GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 2, 0);
              } else 
              if (isRecording == 2) {
                isRecording = 0;
                // STEVE
                // print("END RECORDING!!! GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 1, 1)");
                // print("GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 2, 1)");
                if (!kIsWeb) { 
                  GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 1, 1);
                }
                recordingNotifier.value = [recordingStartTime, DateTime.now().millisecondsSinceEpoch];
              }
              bool isAverageSamples = true;
              arr = processingUtil.processThresholdData(tempData, tempData.length, MediaQuery.of(context).size.width.floor(), selectedThresholdChannel, isAverageSamples);
            }
          } else {
            List<Int16List> tempData = processingUtil.processMicrophoneData(microphoneUtil.micStream.value); 
            tempData.add(Int16List.fromList(tempData[0]));
            // print("PROCESS MICROPHONE DATA LOADED 4 : ${GraphTemplate.isLoadingFile} || TEMPDATA - $tempData");            
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
              if (!kIsWeb) {
                GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 1, 0);
              }
              recordingNotifier.value = [recordingStartTime, DateTime.now().millisecondsSinceEpoch];
              // GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 2, 0);
            } else 
            if (isRecording == 2) {
              isRecording = 0;
              print("ENDING RECORDING GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 2, 1)");
              // STEVE
              if (!kIsWeb) {
                GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 1, 1);
              }
              recordingNotifier.value = [recordingStartTime, DateTime.now().millisecondsSinceEpoch];
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
              // int fromSample = (ProcessingUtil.positionIndex - displayTimeMs * 0.001 * _sampleRate - bufferPaddingLeft).toInt();
              // int fromSample = (-bufferPaddingLeft).toInt();
              // int toSample = (fromSample + displayTimeMs * 0.001 * _sampleRate).toInt();
              int maxSamples = (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
              // print("bufferPaddingLeft : $bufferPaddingLeft | max samples: $maxSamples");
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
  
  int setupFilterValues(List<double> filterValues) {
    startValue = filterValues[0];
    endValue = filterValues[1];
    double type = filterValues[2];
    Provider.of<CustomRangeSliderProvider>(context, listen: false)
        .setStartValue(startValue);
    Provider.of<CustomRangeSliderProvider>(context, listen: false)
        .setEndValue(endValue);
    processingUtil.setBandFilter(startValue, endValue);
    streamScrubBuilderController.add(Random().nextInt(100000));
    if (selectedBoard?.uniqueName == "HUMANSB;") {
      switch (type) {
        case 0: // ECG
          setSerialHpf(false);
          setSerialGain(false);
          break;
        case 1: // EEG
          setSerialGain(true);
          setSerialHpf(false);
          break;
        case 2: // EMG
          setSerialHpf(true);
          setSerialGain(false);
          break;
        case 3: // PLANT
          setSerialHpf(false);
          setSerialGain(false);
          break;
        case 4: // NEURON
          setSerialHpf(false);
          setSerialGain(false);
          break;
      }
    }
    // if () {
    // }
    return 1;
  }
  //https://github.com/BackyardBrains/Spike-Recorder/blob/cdb9686947776ab522027b2078c844b009cb0a33/src/engine/RecordingManager.cpp#L795
  Widget _predefinedFilterSettings() {
    // startValue: startValue,
    // endValue: endValue,
    // sliderValue: _sliderValue,
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        buildSerialUsageTypeButton("ECG"),
        buildSerialUsageTypeButton("EEG"),
        buildSerialUsageTypeButton("EMG"),
        buildSerialUsageTypeButton("Plant"),
        buildSerialUsageTypeButton("Neuron"),

      ],
    );
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
  // bool? isFileOpenedWeb = false;
  Int32List arrConfigWeb = Int32List(10);
  
  bool _isSerialWebButtonEnabled = false;
  
  List<int> visibleSignalsList = [1];
  int visibleChannelCount = 1;
  // Int32List arrSampleCountWeb = Int32List(0);
  // Int16List arrSamplesWeb = Int16List(1);

  void startOpeningFileWeb(String filePath, int startIdx, int endIdx) async {
    currentLoadedFilePath = filePath;
    forceSerialDisconnect = false;
    isOpeningFile = false;

    // Int32List arrConfigWeb = Int32List(10);
    // Int32List arrSampleCount = Int32List(widget.channelCount);
    // Int16List arrSamples = Int16List(1);

    print("======SEEK OPEN FILE - Initiating");
    await GraphTemplate.nwbFileUtil?.startOpeningFileWeb(currentLoadedFilePath, 0, 1, 0, 0);
    // isFileOpenedWeb = await GraphTemplate.nwbFileUtil?.seekElectricalSeries(currentLoadedFilePath, arrSamplesWeb, arrSampleCountWeb, arrConfigWeb, 0, 1, 0, 0);
    print("======SEEK OPEN FILE - FIN");
  }

  void startOpeningFileWebCallbackPlayback(config, arrSampleCount, arrSamples, isStartOpeningFileWeb) async {
    print("SECTION startOpeningFileWebCallbackPlayback : $config, $arrSampleCount, $isStartOpeningFileWeb");
    // [48000, 1, 885, 0, 1000000, 654337, 0, 0, 0, 0], [196301]
    // Validate config before accessing indices to prevent RangeError
    if (config == null || config is! Int32List || config.length < 10) {
      print("ERROR: Invalid config in startOpeningFileWebCallback: $config (type: ${config.runtimeType}, length: ${config is List ? config.length : 'N/A'})");
      return;
    }
    Map<String, dynamic> map = {};
    map["arrSamples"] = arrSamples;
    map["arrSampleCount"] = arrSampleCount;
    map["loadedConfig"] = config;
    seekElectricalSeriesWebCompleter.complete(map);
  }

  void startOpeningFileWebCallback(config, arrSampleCount, arrSamples, isStartOpeningFileWeb) async {
    print("SECTION startOpeningFileWebCallback : $config, $arrSampleCount, $isStartOpeningFileWeb");
    // Validate config before accessing indices to prevent RangeError
    if (config == null || config is! Int32List || config.length < 10) {
      print("ERROR: Invalid config in startOpeningFileWebCallback: $config (type: ${config.runtimeType}, length: ${config is List ? config.length : 'N/A'})");
      return;
    }

    print("GraphTemplate.nwbFileUtil?.recordedNwbFilePath : ${GraphTemplate.nwbFileUtil?.recordedNwbFilePath}");
    if (GraphTemplate.nwbFileUtil?.recordedNwbFilePath == "--") {
      isOpeningFile = false;
      return;
    }

    bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
    print("IS AUDIO LISTEN : $isAudioListen");
    if (!isAudioListen) {
      _serialUtil.isOpeningFile = true;
      _serialUtil.closePort();
      Future.delayed(Duration(milliseconds: 1500), () {
        if (context.mounted) {
          _availablePorts.clear();
        }
      });
    }

    loadedConfig.setAll(0, config);
    widget.channelCount = config[1];
    print("CONFIG WEB CALLBACK: $config");
    loadedMaxSamples = config[5].toDouble();
    int sampleRateConfig = config[0];
    _sampleRate = sampleRateConfig;
    loadedMaxSamples = config[5].toDouble();
    isOpeningFile = true;
    _isSerialWebButtonEnabled = false;
    
    // STEVE: FIX THIS HARDCODED STUFF
    // config[6] might not be set if device detection fails, default to 0 (audio)
    int isSerialDevice = (config.length > 6) ? config[6] : 0;
    // int isSerialDevice = 0;
    print("IS SERIAL DEVICE : $isSerialDevice | CHANNEL COUNT: ${widget.channelCount}");
    if (isSerialDevice == 1) {
      context.read<DataStatusProvider>().setMicrophoneDataStatus(false);
      Provider.of<ConstantProvider>(context, listen: false).setChannelCount(widget.channelCount);     
      Provider.of<SampleRateProvider>(context, listen: false).setSampleRate(sampleRateConfig);     
      ProcessingUtil.initializeDevice.value = (ProcessingUtil.initializeDevice.value * 10) + 2 + Random().nextInt(10);
      context.read<ChannelColorProvider>().setSerialChannelCount(
          widget.channelCount);
      periodicSerialDataSubscription();
      microphoneUtil.micStream.removeListener(micListener);
      microphoneUtil.micStream = ValueNotifier(Uint8List(0));
      // }
    } else {
      context.read<DataStatusProvider>().setMicrophoneDataStatus(true);
      Provider.of<ConstantProvider>(context, listen: false).setChannelCount(widget.channelCount);
      Provider.of<SampleRateProvider>(context, listen: false).setSampleRate(sampleRateConfig);
      ProcessingUtil.initializeDevice.value = 0;
      context.read<ChannelColorProvider>().setAudioChannelCount(widget.channelCount);
      periodicTimerSerial?.cancel();
    }
    print("Loaded Max Samples : $loadedMaxSamples -- ${_sampleRate}");


    loadedConfig[7] = MediaQuery.of(context).size.width.toInt();
    // print("INIT WITH CONFIG: $loadedConfig");
    // await processingUtil.initWithConfig(loadedConfig);
    // print("INIT WITH CONFIG FIN: $loadedConfig");
    
    // Validate arrSampleCount and arrSamples before processing
    if (arrSampleCount == null || arrSamples == null) {
      print("ERROR: arrSampleCount or arrSamples is null. arrSampleCount: $arrSampleCount, arrSamples: $arrSamples");
      return;
    }
    
    // Convert JavaScript arrays to Dart typed lists if needed
    Int32List? arrSampleCountList;
    Int16List? arrSamplesList;

    // seekElectricalSeriesWebCompleter = Completer<Map<String, dynamic>>(); 
    // await GraphTemplate.nwbFileUtil?.seekElectricalSeriesWeb(currentLoadedFilePath, arrSamples, arrSampleCount, loadedConfig, 0, 1, 0, 0);
    // Map<String, dynamic> map = await seekElectricalSeriesWebCompleter.future;
    // arrSamplesList = map['arrSamples'];
    // arrSampleCountList = map['arrSampleCount'];
    // print("RELOAD with correct paramter: ${map['loadedConfig']}");
    // loadedConfig = map['loadedConfig'];
    
    if (arrSampleCount is List) {
      arrSampleCountList = Int32List.fromList(arrSampleCount.map((e) => e as int).toList());
    } else if (arrSampleCount is Int32List) {
      arrSampleCountList = arrSampleCount;
    } else {
      print("ERROR: arrSampleCount is not a valid type: ${arrSampleCount.runtimeType}");
      return;
    }
    
    if (arrSamples is List) {
      arrSamplesList = Int16List.fromList(arrSamples.map((e) => e as int).toList());
    } else if (arrSamples is Int16List) {
      arrSamplesList = arrSamples;
    } else {
      print("ERROR: arrSamples is not a valid type: ${arrSamples.runtimeType}");
      return;
    }
    
    // Validate array sizes
    // if (arrSampleCountList.length < widget.channelCount) {
    //   print("ERROR: arrSampleCount length (${arrSampleCountList.length}) is less than channelCount (${widget.channelCount})");
    //   return;
    // }
    print("Validate Array Sizes 2");    
    int combinedIdx = 0;
    // int totalChannelCount = loadedConfig[1];
    loadedArrSamples.clear();
    loadedArrChannelCount = (Int32List(widget.channelCount));
    print("ZZZ|| arrSampleCount: ${arrSampleCount}");

    for (int i = 0; i < widget.channelCount; i++) {
      // double initialSampleCount = arrSampleCount[i].floor() / totalChannelCount;
      double initialSampleCount = arrSampleCountList != null ? arrSampleCountList[0].toDouble() : arrSampleCount[0].toDouble();
      loadedArrSamples.add(Int16List(initialSampleCount.floor()));
      if (isStartOpeningFileWeb) {
      } else {
        if (arrSamplesList != null && arrSamplesList.length >= combinedIdx + initialSampleCount.floor()) {
          loadedArrSamples[i].setAll(0, arrSamplesList.sublist(combinedIdx, combinedIdx + initialSampleCount.floor()));
        } else if (arrSamples is List && (arrSamples as List).length >= combinedIdx + initialSampleCount.floor()) {
          Int16List tempList = Int16List.fromList((arrSamples as List).sublist(combinedIdx, combinedIdx + initialSampleCount.floor()).map((e) => e as int).toList());
          loadedArrSamples[i].setAll(0, tempList);
        }
      }
      // loadedArrChannelCount.fillRange(0, totalChannelCount, initialSampleCount.floor());
      loadedArrChannelCount[i] = initialSampleCount.floor();
      combinedIdx += initialSampleCount.floor();
    }        
    print("Loaded Arr Samples Status: ${loadedArrSamples.length} || arrSampleCount: ${arrSampleCount}");
    
    // Reset processing buffer when scrubbing (not initial file opening)
    print("IS START OPENING FILE WEB: $isStartOpeningFileWeb | kIsWeb: ${kIsWeb} | widget.channelCount: ${widget.channelCount} | config: $config");
    if (!isStartOpeningFileWeb && kIsWeb) {
      loadedConfig[7] = MediaQuery.of(context).size.width.toInt();
      await processingUtil.initWithConfig(loadedConfig);
    }


    Future.delayed(Duration(milliseconds: 300), () {
      GraphTemplate.isPlayerPaused = true;
      print("START OPENING FILE WEB CALLBACK: ${GraphTemplate.isPlayerPaused}");
      if (isSerialDevice == 0) {
        microphoneUtil.micStream.value = Uint8List(0);
      }
      if (!_pendingPlayback) {
        Provider.of<GraphResumePlayProvider>(context, listen: false).setGraphResumePlay(false);
        GraphTemplate.isLoadingFile = 1;
      }

      print("PROCESSING UTIL: adaptiveAREA SCRUB");
      if (isStartOpeningFileWeb) {
        print("SECTION SCRUB NOTIFIER: $isStartOpeningFileWeb $timeMs");
        AdaptiveAreaState.maxTime = loadedMaxSamples / _sampleRate;
        // AdaptiveAreaState.strMaxTime = loadedMaxSamples / _sampleRate;
        double scrubMaxWidth = MediaQuery.of(context).size.width - 100 - 20;
        // AdaptiveAreaState.horizontalDragX = scrubMaxWidth * 0.3;
        // scrubNotifier.value = [ (scrubMaxWidth * 0.3), scrubMaxWidth];
        double multiplier = _sampleRate / loadedMaxSamples;
        AdaptiveAreaState.horizontalDragX = multiplier * scrubMaxWidth;
        if (multiplier >= 1) {
          AdaptiveAreaState.horizontalDragX = scrubMaxWidth * 0.3;
        }
        scrubNotifier.value = [ (AdaptiveAreaState.horizontalDragX), scrubMaxWidth];
        streamScrubBuilderController.add(Random().nextInt(100000));
      }

      setState(() {
      });
    });
    context.read<GraphDataProvider>().broadcastDisplayTime(10000.0);

    return;    
    
  }

  void startOpeningFile(String filePath) async {
    currentLoadedFilePath = filePath;
    forceSerialDisconnect = false;
    print("INIT NWB FILE");
    isOpeningFile = true;
    bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
    if (!isAudioListen) {
      _serialUtil.closePort();
    }

    Future.delayed(Duration(milliseconds: 1500), () {
      if (context.mounted) {
        _availablePorts.clear();
      }
      // final provider = Provider.of<GraphDataProvider>(context, listen: false);
    });

    
    Int32List arrConfig = Int32List(10);
    Int32List arrSampleCount = Int32List(widget.channelCount);
    Int16List arrSamples = Int16List(1);
    // await GraphTemplate.nwbFileUtil?.readElectricalSeries(arrSampleCount, arrChannelCount, 0, 1);
    // DEMO
    print("======SEEK OPEN FILE - Initiating");
    bool? isFileOpened = await GraphTemplate.nwbFileUtil?.seekElectricalSeries(currentLoadedFilePath, arrSamples, arrSampleCount, arrConfig, 0, 1, 0, 0);
    print("======SEEK OPEN FILE - FIN");
    
    if (isFileOpened != null && !isFileOpened) {
      PanaraInfoDialog.show(
        context,
        textColor: Colors.red,
        title: "Error",
        message: "The file content is not supported",
        buttonText: "Okay",
        onTapDismiss: () {
            Navigator.pop(context);
        },
        panaraDialogType: PanaraDialogType.error,
        barrierDismissible: false,
      );
      isOpeningFile = false;
      return;
    }

    widget.channelCount = arrConfig[1];
    arrSampleCount = Int32List(widget.channelCount);
    loadedMaxSamples = arrConfig[5].toDouble();
    int sampleRateConfig = arrConfig[0];
    
    loadedConfig.setAll(0, arrConfig);
    loadedMaxSamples = arrConfig[5].toDouble();
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
        ProcessingUtil.initializeDevice.value = (ProcessingUtil.initializeDevice.value * 10) + 2 + Random().nextInt(10);
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
    print("Loaded Max Samples : $loadedMaxSamples -- ${_sampleRate}");


    loadedConfig[7] = MediaQuery.of(context).size.width.toInt();
    await processingUtil.initWithConfig(loadedConfig);    
    GraphTemplate.isPlayerPaused = true;
    if (isSerialDevice == 0) {
      microphoneUtil.micStream.value = Uint8List(0);
    }
    Provider.of<GraphResumePlayProvider>(context, listen: false).setGraphResumePlay(false);
    GraphTemplate.isLoadingFile = 1;
    // return;

    AdaptiveAreaState.maxTime = loadedMaxSamples / _sampleRate;
    // AdaptiveAreaState.strMaxTime = loadedMaxSamples / _sampleRate;
    double scrubMaxWidth = MediaQuery.of(context).size.width - 100 - 20;
    // AdaptiveAreaState.horizontalDragX = scrubMaxWidth * 0.3;
    // scrubNotifier.value = [ (scrubMaxWidth * 0.3), scrubMaxWidth];
    double multiplier = _sampleRate / loadedMaxSamples;
    AdaptiveAreaState.horizontalDragX = multiplier * scrubMaxWidth;
    if (multiplier >= 1) {
      AdaptiveAreaState.horizontalDragX = scrubMaxWidth * 0.3;
    }
    scrubNotifier.value = [ (AdaptiveAreaState.horizontalDragX), scrubMaxWidth];
    streamScrubBuilderController.add(Random().nextInt(100000));


    setState(() {
      
    });
    return;
    
    print("sampleRateConfig: $sampleRateConfig $arrConfig");
    double arrSamplesLength = ProcessingUtil.MAX_DISPLAY_SECONDS * sampleRateConfig;
    // double arrSamplesLength = loadedMaxSamples;
    // double arrSamplesLength = maxSamples.toDouble();
    
    // // Calculate total data points needed for multi-channel reading
    // int samplesPerChannel = arrSamplesLength.floor();
    // int numChannels = 2; // Reading channels 0-1
    // int totalDataPoints = samplesPerChannel * numChannels;

    arrSamples = Int16List(arrSamplesLength.floor() * widget.channelCount);

    // await GraphTemplate.nwbFileUtil?.seekElectricalSeries(arrSamples, arrSampleCount, arrConfig, 0, arrSamplesLength.floor(), 0, 1);
    double startSeekSample = 0;
    double endSeekSample = arrSamplesLength; // (arrSamplesLength - startSeekSample).floor()
    startSeekSampleIdx = startSeekSample;
    endSeekSampleIdx = endSeekSample;
    if (endSeekSampleIdx > loadedMaxSamples) {
      endSeekSampleIdx = loadedMaxSamples;
      endSeekSample = loadedMaxSamples.toDouble();
    }
    // endSeekSampleIdx = loadedMaxSamples;
    // endSeekSample = loadedMaxSamples.toDouble();

    await Future.delayed(Duration(milliseconds: 100));

    print("FINISH WAITINGGGGGG END SEEK SAMPLE IDX: $endSeekSampleIdx $loadedMaxSamples");
    await GraphTemplate.nwbFileUtil?.seekElectricalSeries(currentLoadedFilePath, arrSamples, arrSampleCount, loadedConfig, (startSeekSample).floor(), endSeekSample.floor(), 0, widget.channelCount - 1);
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
    // print("OPENING FILE loadedArrSamples: ${loadedArrSamples[1].sublist(0, 10)}");
    loadedConfig[7] = MediaQuery.of(context).size.width.toInt();
    processingUtil.initWithConfig(loadedConfig);

    GraphTemplate.isPlayerPaused = true;
    microphoneUtil.micStream.value = Uint8List(0);
    print("setGraphResumePlay PLAYBACK INIT : $combinedIdx | $totalChannelCount");
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
      print("Graph Template isLoadingFile: ${GraphTemplate.isLoadingFile}");
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
      // print("SAMPLES COUNT: $samplesCount");
      // print("WIDGET CHANNEL COUNT: $widget.channelCount");
      // processingUtil.processingNwbFileInjectData(flattenedList, samplesCount, 0, widget.channelCount);
      processingUtil.processingSerialDataResult(flattenedList, samplesCount, widget.channelCount);
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
          if (!kIsWeb) {
            GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, widget.channelCount, 0);
          }
          recordingNotifier.value = [recordingStartTime, DateTime.now().millisecondsSinceEpoch];
          // GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 2, 0);
        } else 
        if (isRecording == 2) {
          // STEVE
          // print("END RECORDING!!! GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, ${widget.channelCount}, 1)");
          // print("GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 2, 1)");
          if (!kIsWeb) {
            GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, widget.channelCount, 1);
          }
          recordingNotifier.value = [recordingStartTime, DateTime.now().millisecondsSinceEpoch];
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
    periodicTimerSerial =Timer.periodic(Duration(milliseconds: timeMs), (timer){
      bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
      // List<String> listOfPort = Provider.of<PortScanProvider>(context, listen: false).availablePorts;
      serialNativeDataSubscription(Uint8List(0), isAudioListen);
    });
  }
  
  List<Widget> generateThresholdSlider(isHorizontal) {
    if (!kIsWeb && isHorizontal && Platform.isAndroid) {
      return [];
    }
    return  [
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
        width: 200,
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
    ];
  }
  
  void initMessageIdentifier() {
    _messageIdentifier = MessageIdentifier(onDeviceData: (Uint8List dt) {
      if (forceSerialDisconnect) return;
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
      if (forceSerialDisconnect) return;
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
          // if (foundDevices == "MUSCLESS") {
          //   foundDevices = "HEARTSS";
          // }
          

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
                  if (!kIsWeb) {
                    print("microphoneUtil.micStatus?.cancel()");
                    microphoneUtil.micStatus?.cancel();
                  }

                  
                  deviceChannelCount = int.parse(board.maxNumberOfChannels!);
                  context.read<ChannelColorProvider>().setSerialChannelCount(
                      int.parse(board.maxNumberOfChannels!));
                  context.read<ChannelFilterProvider>().setSerialChannelCount(
                      int.parse(board.maxNumberOfChannels!));
                  // createDisplaySerialDataIsolate();
                  // createProcessSerialDataIsolate();
                  Future.delayed(Duration(seconds: 2), (){
                    // var info = processingUtil.getInformation();
                    // print("info : $info");
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

  }
  
  void _startPlaybackTimer() {
    print("START PLAYBACK TIMER");
    timerPlaybackLoadedFile?.cancel();
    timerPlaybackLoadedStartIndex = 0;
    timerPlaybackLoadedEndIndex = 0;
    double playbackFactor = _sampleRate / 1000;
    bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
    
    Future.delayed(Duration(milliseconds: 100), () {
      int prevTime = DateTime.now().millisecondsSinceEpoch;
      bool isPlayback = true;
      timerPlaybackLoadedFile = Timer.periodic(Duration(milliseconds: 50), (timer) async {
        GraphTemplate.isLoadingFile = 4;
        int timeDiff = DateTime.now().millisecondsSinceEpoch - prevTime;
        sampleDivider = (timeDiff * playbackFactor);
        prevTime = DateTime.now().millisecondsSinceEpoch;
        
        try {
          timerPlaybackLoadedEndIndex = timerPlaybackLoadedStartIndex + sampleDivider;
          if (startPlaybackSeekSampleIdx + timerPlaybackLoadedEndIndex > loadedMaxSamples) {
            timerPlaybackLoadedEndIndex = loadedArrSamples[0].length - 1;
          }

          List<Int16List> sublistArray = [];
          print("loadedArrSamples: Channel: ${widget.channelCount} --- $timerPlaybackLoadedStartIndex $timerPlaybackLoadedEndIndex || ${loadedArrSamples.length}");
          for (int i = 0; i < widget.channelCount; i++) {
            Int16List sublistSamples = loadedArrSamples[i].sublist(timerPlaybackLoadedStartIndex.floor(), timerPlaybackLoadedEndIndex.floor());
            sublistArray.add(sublistSamples);
            soloud!.addAudioDataStream(loadedFileStreams[i]!, sublistSamples.buffer.asUint8List());
          }
          timerPlaybackLoadedStartIndex = (timerPlaybackLoadedStartIndex + sampleDivider);
          
          if (startPlaybackSeekSampleIdx + timerPlaybackLoadedStartIndex > loadedMaxSamples) {
            timerPlaybackLoadedStartIndex = loadedMaxSamples - 1;
            double startSeekSampleLocal = endSeekSampleIdx.toDouble();
            double endSeekSampleLocal = loadedMaxSamples.toDouble();
            startPlaybackSeekSampleIdx = startSeekSampleLocal;
            endSeekSampleIdx = endSeekSampleLocal;

            print("ARR SAMPLES ZERO STOPPING");
            Provider.of<GraphResumePlayProvider>(context, listen: false).setGraphResumePlay(false);
            Int32List arrSampleCount = Int32List(widget.channelCount);
            Int16List arrSamples = Int16List((endSeekSampleIdx.floor() - startPlaybackSeekSampleIdx.floor()) * widget.channelCount);
            if (startSeekSampleLocal != endSeekSampleLocal) {
              await GraphTemplate.nwbFileUtil?.seekElectricalSeries(currentLoadedFilePath, arrSamples, arrSampleCount, loadedConfig, (startSeekSampleLocal).floor(), endSeekSampleLocal.floor(), 0, widget.channelCount - 1);
            }
            GraphTemplate.isLoadingFile = 2;
            GraphTemplate.isPlayerPaused = true;

            timerPlaybackLoadedStartIndex = 0;
            timerPlaybackLoadedEndIndex = 0;
            startPlaybackSeekSampleIdx = 0;
            endSeekSampleIdx = 0;

            double playbackPercentage = (startPlaybackSeekSampleIdx + timerPlaybackLoadedStartIndex) / (loadedMaxSamples);
            AdaptiveAreaState.horizontalDragX = playbackPercentage * AdaptiveAreaState.horizontalDragXFix;
            print("AdaptiveAreaState.horizontalDragX :  ${AdaptiveAreaState.horizontalDragX}");

            timerPlaybackLoadedFile?.cancel();
            setState(() {});
            return;
          }

          // On web, add samples to audio stream as playback progresses
          // if (kIsWeb && soloud != null && loadedFileStreams.isNotEmpty && isPlayback) {
          //   isPlayback = false;
          //   for (int i = 0; i < widget.channelCount && i < sublistArray.length && i < loadedFileStreams.length; i++) {
          //     if (sublistArray[i].isNotEmpty) {
          //       soloud!.addAudioDataStream(loadedFileStreams[i]!, sublistArray[i].buffer.asUint8List());
          //     }
          //   }
          // }

          if (isAudioListen) {
            GraphTemplate.isLoadingFile = 3;
            processingUtil.processMicrophoneData(sublistArray[0].buffer.asUint8List());
            microphoneUtil.micStream.value = Uint8List(0);
          } else {
            GraphTemplate.isLoadingFile = 4;
            int channelIdx = 0;
            Int32List samplesCount = Int32List(sublistArray.length);
            Int16List flattenedList = Int16List.fromList(sublistArray.expand((list) {
              samplesCount[channelIdx] = sublistArray[channelIdx].length;
              channelIdx++;
              return list;
            }).toList());
            processingUtil.processingSerialDataResult(flattenedList, samplesCount, widget.channelCount);
          }

          double playbackPercentage = (startPlaybackSeekSampleIdx + timerPlaybackLoadedStartIndex) / (loadedMaxSamples);
          AdaptiveAreaState.horizontalDragX = playbackPercentage * AdaptiveAreaState.horizontalDragXFix;

          setState(() {});
        } catch(err) {
          print("ERR: $err ||| $timerPlaybackLoadedEndIndex | $timerPlaybackLoadedStartIndex ");
        }
      });
    });
  }
  
  void callbackPlayButton(bool isPlay) async {
    // 1. UI settings
    print("setGraphResumePlay PLAYBACK PAUSE BUTTON");
    Provider.of<GraphResumePlayProvider>(context, listen: false).setGraphResumePlay(isPlay);
    print("setGraphResumePlay PLAYBACK PAUSE BUTTON 22");
    _toPauseGraph = isPlay;
    print("setGraphResumePlay PLAYBACK PAUSE BUTTON 44");
    GraphTemplate.isPlayerPaused = !isPlay;
    print("setGraphResumePlay GraphTemplate.isPlayerPaused | SAMPLE RATEZ: $_sampleRate");

    // 2. SoLoud initialization
    if (soloud == null) {
      soloud = SoLoud.SoLoud.instance;
      await soloud!.init(
        bufferSize: 512,
        sampleRate: _sampleRate,
        channels: SoLoud.Channels.mono,
      );
    }
    print("setGraphResumePlay GraphTemplate.isPlayerPaused 2");    
    bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
    print("IS PLAY $isPlay");
    if (!isPlay) {
      // print("STOP SOUND | ${widget.channelCount} | ::: ${soloud?.getStreamTimeConsumed(loadedFileStreams[0]!)}");
      timerPlaybackLoadedFile?.cancel();

      if (soloud != null) {
        // double maxSamplesTime = loadedMaxSamples / _sampleRate * 1000;
        double sampleConsumed = (soloud?.getStreamTimeConsumed(loadedFileStreams[0]!))!.inMilliseconds / 2 * _sampleRate / 1000;
        startPlaybackSeekSampleIdx += timerPlaybackLoadedStartIndex;
        startSeekSampleIdx = startPlaybackSeekSampleIdx;
        // startPlaybackSeekSampleIdx -= sampleDivider;
        print("STOP SOUND | ${widget.channelCount} | ${(soloud?.getStreamTimeConsumed(loadedFileStreams[0]!))!.inMilliseconds} | ::: $sampleConsumed ::: $timerPlaybackLoadedStartIndex");
      }
      for (int i = 0; i < widget.channelCount; i++) {
        soloud?.setDataIsEnded(loadedFileStreams[i]!);
        soloud?.stop(loadedSoundHandles[i]!);
      }
      GraphTemplate.isLoadingFile = 2;
      // startPlaybackSeekSampleIdx += timerPlaybackLoadedStartIndex;
      // endSeekSampleIdx += timerPlaybackLoadedEndIndex;
      // timerPlaybackLoadedStartIndex = 0;
      // timerPlaybackLoadedEndIndex = 0;
      setState((){});

    } else {
      loadedFileStreams.clear();


      // print("ADDED FILE STREAMS : $_sampleRate || $startPlaybackSeekSampleIdx ||| $percentage || SCRUB: ${scrubNotifier.value}");
      // 3. SoLoud buffer stream setup
      print("widget.channelCount: ${widget.channelCount} ${_sampleRate}");
      for (int i = 0; i < widget.channelCount; i++) {
        if (Platform.isAndroid) {
          loadedFileStreams.add(soloud!.setBufferStream(
            // maxBufferSizeBytes: 1024 * 1024 * 10,
            // {Size} = {Sample Rate} * {Bytes per Sample} * {MONO CHANNEL} * {Desired Seconds} * {100  constant}
            bufferingType: SoLoud.BufferingType.released,
            sampleRate: _sampleRate,
            channels: SoLoud.Channels.mono,
            format: SoLoud.BufferType.s16le,
            onBuffering: (isBuffering, handle, time) async {
              print("IS BUFFERING $isBuffering $handle $time");
              if (context.mounted) {

              }
            },
          ));

        } else {          
          loadedFileStreams.add(soloud!.setBufferStream(
            // maxBufferSizeBytes: 1024 * 1024 * 10,
            // {Size} = {Sample Rate} * {Bytes per Sample} * {MONO CHANNEL} * {Desired Seconds} * {100  constant}
            maxBufferSizeBytes: _sampleRate * 2 * 1 * 10 ,
            bufferingTimeNeeds: 0.05,
            bufferingType: SoLoud.BufferingType.released,
            sampleRate: _sampleRate,
            channels: SoLoud.Channels.mono,
            format: SoLoud.BufferType.s16le,
            onBuffering: (isBuffering, handle, time) async {
              print("IS BUFFERING $isBuffering $handle $time");
              if (context.mounted) {

              }
            },
          ));
        }
      }
      
      
      // insert old samples, if samplesLength == 0 return null,
      // List<int> timeScrub = scrubNotifier.value;
      // double percentage = 0;
      // if (timeScrub.isNotEmpty) {
      //   percentage = timeScrub[0] / timeScrub[1];
      // }      
      // startPlaybackSeekSampleIdx = percentage * loadedMaxSamples;      

      // 4. Seek sample index setup
      double startSeekSample = startPlaybackSeekSampleIdx.toDouble();
      double maxScreenSamples = ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate; 
      double endSeekSample = 0; // (arrSamplesLength - startSeekSample).floor()
      print("TIME 0 $startSeekSample | $maxScreenSamples | $loadedMaxSamples | $endSeekSample");
      // scenario 1: 3 seconds recorded audio : start 0 => END 210000
      // scenario 2: 700000 samples recorded audio : start 200000 => END 680000  
      if (loadedMaxSamples < maxScreenSamples) {
        endSeekSample = loadedMaxSamples.toDouble();
      } else {
        if (startPlaybackSeekSampleIdx + maxScreenSamples > loadedMaxSamples) {
          endSeekSample = loadedMaxSamples.toDouble();
        } else {
          endSeekSample = loadedMaxSamples.toDouble();
        }
      }
      // startPlaybackSeekSampleIdx = startSeekSample;
      // endSeekSampleIdx = endSeekSample.floor();
      endSeekSampleIdx = (loadedMaxSamples - startSeekSample);

      Int32List arrSampleCount = Int32List(widget.channelCount);
      // Int16List arrSamples = Int16List(loadedMaxSamples - startPlaybackSeekSampleIdx);
      Int16List arrSamples = Int16List(loadedMaxSamples.toInt() * widget.channelCount);
      // await GraphTemplate.nwbFileUtil?.seekElectricalSeries(arrSamples, arrSampleCount, loadedConfig, (startSeekSample).floor(), endSeekSample.floor(), 0, 1);
      // await GraphTemplate.nwbFileUtil?.seekElectricalSeries(arrSamples, arrSampleCount, loadedConfig, (startSeekSample).floor(), (loadedMaxSamples).floor(), 0, 1);
      print("======SEEK 1 ");
      
      // On web, seekElectricalSeries is async via callback, so we need to wait for data
      if (kIsWeb) {
        _pendingPlayback = true;
        _pendingPlaybackStartIdx = startPlaybackSeekSampleIdx;
        seekElectricalSeriesWebCompleter = Completer<Map<String, dynamic>>(); 
        
        // Filling SoLoud buffer with samples
        await GraphTemplate.nwbFileUtil?.seekElectricalSeriesWeb(currentLoadedFilePath, arrSamples, arrSampleCount, loadedConfig, (startPlaybackSeekSampleIdx).floor(), (loadedMaxSamples).floor(), 0, widget.channelCount - 1);
        await seekElectricalSeriesWebCompleter.future.then((map) async {
          arrSamples = map['arrSamples'];
          arrSampleCount = map['arrSampleCount'];
          loadedConfig = map['loadedConfig'];
          print("SEEK ELECTRICAL SERIES WEB COMPLETED: $loadedConfig");
          // print("arrSampleCount : $arrSampleCount | arrSamplesLength: ${arrSamples.length}");
          // print("arrSamples : $arrSamples");

          int combinedIdx = 0;
          int totalChannelCount = loadedConfig[1];
          loadedArrSamples.clear();
          loadedArrChannelCount = (Int32List(widget.channelCount));
          try {
            for (int i = 0; i < widget.channelCount; i++) {
              // double initialSampleCount = arrSampleCount[i].floor() / totalChannelCount;
              // HARDCODE!
              double initialSampleCount = arrSampleCount[i].toDouble();
              loadedArrSamples.add(Int16List(initialSampleCount.floor()));
              loadedArrSamples[i].setAll(0, arrSamples.sublist(combinedIdx, combinedIdx + initialSampleCount.floor()));
              // loadedArrChannelCount.fillRange(0, totalChannelCount, initialSampleCount.floor());
              loadedArrChannelCount[i] = initialSampleCount.floor();
              combinedIdx += initialSampleCount.floor();
              // soloud!.addAudioDataStream(loadedFileStreams[i]!, loadedArrSamples[i].buffer.asUint8List());
            }
            // soloud!.setVisualizationEnabled(true);
          }catch(err) {
            print("ERR: $err | arrSampleCount: $arrSampleCount -- channelCount: ${widget.channelCount}");
          }

          print("ADDED DATA STREAM Channel Count: ${widget.channelCount}");

          // Start playback timer (non-web path)
          
          loadedSoundHandles.clear();
          if (isAudioListen) {
            for (int i = 0; i < widget.channelCount; i++) {
              print("Initialize PLAY SOUND ${DateTime.now().millisecondsSinceEpoch}");
              soloud!.play(loadedFileStreams[i]!).then((soundHandle) {
                print("Start PLAY SOUND ${DateTime.now().millisecondsSinceEpoch}");
                loadedSoundHandles.add(soundHandle);
                _startPlaybackTimer();

                // loadedSoundHandles[i] = soundHandle;
              });
            }
            // Future.delayed(Duration(milliseconds: 100), () {
            // });
          } else {
            for (int i = 0; i < widget.channelCount; i++) {
              soloud!.play(loadedFileStreams[i]!).then((soundHandle) {
                loadedSoundHandles.add(soundHandle);
                // loadedSoundHandles[i] = soundHandle;
              });
            }
            Future.delayed(Duration(milliseconds: 100), () {
              _startPlaybackTimer();
            });
          }
          
          print("ADDED DATA STREAM2");


          GraphTemplate.isLoadingFile = 3;
          loadedConfig[7] = MediaQuery.of(context).size.width.toInt();
          await processingUtil.initWithConfig(loadedConfig);
          print("START SEEK SAMPLE INITIAL 0000 $startPlaybackSeekSampleIdx | ${arrSampleCount[0].floor()} == $loadedMaxSamples");
          if (startPlaybackSeekSampleIdx > 0 && arrSampleCount[0].floor() > 0) {
            int startInitialIndex = (startPlaybackSeekSampleIdx - maxScreenSamples.floor()).floor();
            startInitialIndex = startInitialIndex > 0 ? startInitialIndex : 0;
            // int endInitialIndex = startInitialIndex + (startSeekSample % maxScreenSamples.floor()).floor();
            int endInitialIndex = (startPlaybackSeekSampleIdx).floor();
            Int32List arrSampleCountInitial = Int32List(widget.channelCount);
            Int16List arrSamplesInitial = Int16List(endInitialIndex * widget.channelCount);
            print("Start Initial Index: $startInitialIndex | End Initial Index: $endInitialIndex");

            // hardcode
            bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
            if (isAudioListen) {
              seekElectricalSeriesWebCompleter = Completer<Map<String, dynamic>>(); 
              await GraphTemplate.nwbFileUtil?.seekElectricalSeriesWeb(currentLoadedFilePath, arrSamplesInitial, arrSampleCountInitial, loadedConfig, startInitialIndex, endInitialIndex, 0, 0);
              Map<String, dynamic> map = await seekElectricalSeriesWebCompleter.future;
              // print("SEEK ELECTRICAL SERIES WEB COMPLETED2: $map | $startInitialIndex | $endInitialIndex");
              arrSamplesInitial = map['arrSamples'];
              arrSampleCountInitial = map['arrSampleCount'];
              var loadedConfigLocal = map['loadedConfig'];

              Int16List tempLoadedArrSamples = Int16List(arrSampleCountInitial[0].floor());
              tempLoadedArrSamples.setAll(0, arrSamplesInitial.sublist(0, arrSampleCountInitial[0].floor()));
              processingUtil.processMicrophoneData(tempLoadedArrSamples.buffer.asUint8List());
              print("----> START SEEK SAMPLE INITIAL : $startInitialIndex |=| ${(startSeekSample % maxScreenSamples.floor()).floor()} | ${arrSampleCountInitial[0].floor()} |  ${tempLoadedArrSamples.length} |||| ${tempLoadedArrSamples.buffer.asUint8List().length}");
              microphoneUtil.micStream.value = Uint8List(0);

            } else {
              // FIX TOMORROW
              seekElectricalSeriesWebCompleter = Completer<Map<String, dynamic>>(); 
              await GraphTemplate.nwbFileUtil?.seekElectricalSeriesWeb(currentLoadedFilePath, arrSamplesInitial, arrSampleCountInitial, loadedConfig, startInitialIndex, endInitialIndex, 0, widget.channelCount - 1);
              Map<String, dynamic> map = await seekElectricalSeriesWebCompleter.future;
              arrSamplesInitial = map['arrSamples'];
              arrSampleCountInitial = map['arrSampleCount'];
              var loadedConfigLocal = map['loadedConfig'];

              print("FIX TOMORROW: arrSamplesInitial: Widget Channel Length: ${widget.channelCount} ||| arrSamplesInitial: ${arrSamplesInitial.length} ||| arrSampleCountInitial: ${arrSampleCountInitial} ||| endInitialIndex: ${arrSampleCountInitial[0]}");
              List<Int16List> sublistArray = [];
              for (int i = 0; i < widget.channelCount; i++) {
                // HARDCODE!
                int samplesPerChannelLength = arrSampleCountInitial[0].floor();
                sublistArray.add(arrSamplesInitial.sublist(i * samplesPerChannelLength, (i + 1) * samplesPerChannelLength));
                // soloud!.addAudioDataStream(loadedFileStream!, sublistArray);
              }

              int channelIdx = 0;
              Int32List samplesCount = Int32List(sublistArray.length);
              Int16List flattenedList = Int16List.fromList(sublistArray.expand((list) {
                samplesCount[channelIdx] = sublistArray[channelIdx].length;
                // print("SAMPLES COUNT: ${samplesCount[channelIdx]}");
                channelIdx++;
                return list;
              }).toList());

              processingUtil.processingSerialDataResult(flattenedList, samplesCount, widget.channelCount);
            }
          } else {
            GraphTemplate.isLoadingFile = 4;
            // microphoneUtil.micStream.value = Uint8List(0);
          }

          // soloud!.addAudioDataStream(loadedFileStream!, loadedArrSamples.buffer.asUint8List());
                 

        });
        return;
      } else {
        await GraphTemplate.nwbFileUtil?.seekElectricalSeries(currentLoadedFilePath, arrSamples, arrSampleCount, loadedConfig, (startPlaybackSeekSampleIdx).floor(), (loadedMaxSamples).floor(), 0, widget.channelCount - 1);
      }
      
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

      print("ADDED DATA STREAM Channel Count: ${widget.channelCount}");

      // Start playback timer (non-web path)
      _startPlaybackTimer();
      
      Future.delayed(Duration(milliseconds: 100), () {
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
      // 5. Seek previous samples and combine with the new samples from playback
      print("START SEEK SAMPLE INITIAL 0000 $startPlaybackSeekSampleIdx ${arrSampleCount[0].floor()} == $loadedMaxSamples");
      if (startPlaybackSeekSampleIdx > 0 && arrSampleCount[0].floor() > 0) {
        // int startInitialIndex = (startPlaybackSeekSampleIdx ~/ maxScreenSamples.floor()) * maxScreenSamples.floor();
        int startInitialIndex = (startPlaybackSeekSampleIdx - maxScreenSamples.floor()).floor();
        startInitialIndex = startInitialIndex > 0 ? startInitialIndex : 0;
        // int endInitialIndex = startInitialIndex + (startSeekSample % maxScreenSamples.floor()).floor();
        int endInitialIndex = (startPlaybackSeekSampleIdx).floor();
        Int32List arrSampleCountInitial = Int32List(widget.channelCount);
        Int16List arrSamplesInitial = Int16List(endInitialIndex * widget.channelCount);
        print("Start Initial Index: $startInitialIndex | End Initial Index: $endInitialIndex"); 

        bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
        if (isAudioListen) {
          await GraphTemplate.nwbFileUtil?.seekElectricalSeries(currentLoadedFilePath, arrSamplesInitial, arrSampleCountInitial, loadedConfig, startInitialIndex, endInitialIndex, 0, 0);
          Int16List tempLoadedArrSamples = Int16List(arrSampleCountInitial[0].floor());
          tempLoadedArrSamples.setAll(0, arrSamplesInitial.sublist(0, arrSampleCountInitial[0].floor()));
          processingUtil.processMicrophoneData(tempLoadedArrSamples.buffer.asUint8List());
          print("----> START SEEK SAMPLE INITIAL : $startInitialIndex |=| ${(startSeekSample % maxScreenSamples.floor()).floor()} | ${arrSampleCountInitial[0].floor()} |  ${tempLoadedArrSamples.length} |||| ${tempLoadedArrSamples.buffer.asUint8List().length}");
          microphoneUtil.micStream.value = Uint8List(0);
        } else {
          // FIX TOMORROW
          await GraphTemplate.nwbFileUtil?.seekElectricalSeries(currentLoadedFilePath, arrSamplesInitial, arrSampleCountInitial, loadedConfig, startInitialIndex, endInitialIndex, 0, widget.channelCount - 1);
          print("FIX TOMORROW: arrSamplesInitial: ${arrSamplesInitial.length} ||| arrSampleCountInitial: ${arrSampleCountInitial} ||| endInitialIndex: ${arrSampleCountInitial[0]}");
          List<Int16List> sublistArray = [];
          for (int i = 0; i < widget.channelCount; i++) {
            int samplesPerChannelLength = arrSampleCountInitial[i].floor();
            sublistArray.add(arrSamplesInitial.sublist(i * samplesPerChannelLength, (i + 1) * samplesPerChannelLength));
            // soloud!.addAudioDataStream(loadedFileStream!, sublistArray);
          }

          int channelIdx = 0;
          Int32List samplesCount = Int32List(sublistArray.length);
          Int16List flattenedList = Int16List.fromList(sublistArray.expand((list) {
            samplesCount[channelIdx] = sublistArray[channelIdx].length;
            // print("SAMPLES COUNT: ${samplesCount[channelIdx]}");
            channelIdx++;
            return list;
          }).toList());

          processingUtil.processingSerialDataResult(flattenedList, samplesCount, widget.channelCount);
        }
      } else {
        GraphTemplate.isLoadingFile = 4;
        // microphoneUtil.micStream.value = Uint8List(0);
      }
      // soloud!.addAudioDataStream(loadedFileStream!, loadedArrSamples.buffer.asUint8List());
    }    
  }
  
  void stopCurrentPlaying() {
    try{
      if (soloud != null) {
        print("listenToMicrophone soloud != null ");
        for (int i = 0; i < loadedSoundHandles.length; i++) {
          soloud?.stop(loadedSoundHandles[i]!);
        }
        soloud = null;
      } else {
        print("listenToMicrophone soloud == null ");
      }

      timerPlaybackLoadedFile?.cancel();
      timerPlaybackLoadedFile = null;
      timerPlaybackLoadedStartIndex = 0;
      timerPlaybackLoadedEndIndex = 0;
      loadedMaxSamples = 0;
      loadedConfig = Int32List(10);
      loadedArrSamples = [];
      loadedArrChannelCount = Int32List(1);
      startSeekSampleIdx = 0;
      endSeekSampleIdx = 0;
      scrubNotifier.value = [];
      recordingNotifier.value = [0,0];
      soloud = null;
      loadedFileStreams = [];
      loadedSoundHandles = [];
      isOpeningFile = false;
      getData = null;
      periodicTimerSerial?.cancel();
    }catch(err){
      print("er listenToMicrophone");
      print(err);
    }

  }
  
  serialWebButton() {
    return kIsWeb
      ? isRecording != 0 ? SizedBox() : 
        ElevatedButton(
          // elevation: 2,
          // shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(width: 2, color: Colors.grey)),
          // backgroundColor: SoftwareColors.kButtonBackGroundColor,
          style: ElevatedButton.styleFrom(
            shape: const CircleBorder(), // This makes the shape circular
            padding: const EdgeInsets.all(20), // Controls the size of the button
            backgroundColor: SoftwareColors.kButtonBackGroundColor, // Button color
          ),
          onPressed: () async {
            if (_isSerialWebButtonEnabled) {
              _isSerialWebButtonEnabled = false;
              _serialUtil.closePort();
              isDeviceConnect = false;
              isDeviceSelected = false;
              _isDataIdentified = false;
              GraphDataProvider graphDataProvider = Provider.of<GraphDataProvider>(context, listen: false);
              listenToMicrophone(1, graphDataProvider);
              streamScrubBuilderController.add(Random().nextInt(100000));

              return;
            }
            _isSerialWebButtonEnabled = true;
            try {
              int baudRate = context.read<ConstantProvider>().getBaudRate();
              print("getAvailablePorts: $baudRate");
              List<String> availablePorts = await _serialUtil.getAvailablePortsWeb(baudRate, serialErrorCallback);
              if (availablePorts.isEmpty) {
                _isSerialWebButtonEnabled = false;
                return;
              }
              print("availablePorts GRAPH TEMPLATE: $availablePorts");

              Provider.of<GraphResumePlayProvider>(context, listen: false).setGraphResumePlay(false);
              GraphTemplate.isLoadingFile = 0;
              isOpeningFile = false;
              bool isPlay = true;
              Provider.of<GraphResumePlayProvider>(context, listen: false).setGraphResumePlay(isPlay);
              _toPauseGraph = isPlay;
              GraphTemplate.isPlayerPaused = !isPlay;
              _pendingPlayback = false;


              serialDataSubscription?.cancel();
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
              streamScrubBuilderController.add(Random().nextInt(100000));

              serialDataSubscription = _serialUtil.dataStream?.listen((event) async {
                if (isOpeningFile) {
                  return;
                }
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
                      if (isRecording == 1) {
                        recordingNotifier.value = [recordingStartTime, DateTime.now().millisecondsSinceEpoch];
                      }
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
                      Future.delayed(Duration(milliseconds:100), () {
                        Uint8List commandBytes = Uint8List.fromList(utf8.encode("board:;"));
                        _serialUtil.writeToPort(bytesMessage: commandBytes, address: _availablePorts.last);
                      });
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

              }, onError: (error) {
                // if (error is SerialPortError) {
                  forceSerialDisconnect = true;
                  print("SERIAL PORT ERROR -- DISCONNECTED");
                  _serialUtil.closePort();
                  Future.delayed(Duration(milliseconds: 2500), () {
                    forceSerialDisconnect = false;
                    _isSerialWebButtonEnabled = false;
                    isDeviceConnect = false;
                    isDeviceSelected = false;
                    _isDataIdentified = false;
                    streamScrubBuilderController.add(Random().nextInt(100000));
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
          child: Row(
            children: [
              Icon(
                Icons.usb,
                size: 25,
                color: _isSerialWebButtonEnabled ? Colors.yellow : SoftwareColors.kButtonColor,
              )
            ],
          ),
        )
      : Container();    
  }
  
  void resetRecordingState(widgetContext) {
    if (isRecording == 1) {
      if (kIsWeb) {
        GraphTemplate.nwbFileUtil?.addElectricalSeries(Int16List(0), Int32List(0), 0, 1, 1);
      }
      isRecording = 0;
      GraphTemplate.nwbFileUtil?.recordedNwbFilePath = "";
    } else {
      isRecording = 0;
    }
    context.read<ChannelColorProvider>().setIsRecording(0);

    print("STOP RECORDING");
    Future.delayed(Duration(milliseconds: 300), () async {
      recordingNotifier.value = [0, 0];
      if (recordedFilePath != null && recordedFilePath != "false") {
        if (widgetContext.mounted) {
          if (!kIsWeb) {
            if (Platform.isAndroid) {
              String? publicPath = "";
              if (recordedFilePath != null) {
                publicPath = await GraphTemplate.nwbFileUtil?.makeFilePublic(recordedFilePath!);
              }
              ScaffoldMessenger.of(widgetContext).showSnackBar(SnackBar(content: Text("File recorded successfully: $publicPath"), duration: Duration(seconds: 7),));
            } else {
              ScaffoldMessenger.of(widgetContext).showSnackBar(SnackBar(content: Text("File recorded successfully: $recordedFilePath"), duration: Duration(seconds: 7),));
            }
          } else {
            // Web platform - file download is handled automatically
            // ScaffoldMessenger.of(widgetContext).showSnackBar(SnackBar(content: Text("File recorded successfully: $recordedFilePath"), duration: Duration(seconds: 7),));
          }
        }
      }
      setState((){});

    });    
  }
  
  


  serialErrorCallback(int channelCount, provider) {
    print("SERIAL ERROR CALLBACK");
    if (isRecording > 0) {
      resetRecordingState(context);
    }
    print("End Reset Recording State");
    final provider = Provider.of<GraphDataProvider>(context, listen: false);
    Future.delayed(Duration(seconds: 1), () {
      print("Listen To Microphone Serial Error");
      listenToMicrophone(1, provider);
    });
  }
  
  void setSerialHpf(bool active) {
    String sstm;
    if(active)
    {
        sstm = "hpfon:2;hpfon:1;\n";
    }
    else
    {
        sstm = "hpfoff:2;hpfoff:1;\n";
    }    
    _serialUtil.writeToPort(bytesMessage: Uint8List.fromList(utf8.encode(sstm)), address: _availablePorts.last);
  }

  void setSerialGain(bool active) {
    String sstm;
    if(active)
    {
        sstm = "gainon:2;gainon:1;\n";
    }
    else
    {
        sstm = "gainoff:2;gainoff:1;\n";
    }    
    _serialUtil.writeToPort(bytesMessage: Uint8List.fromList(utf8.encode(sstm)), address: _availablePorts.last);
  }
  
  buildSerialUsageTypeButton(String s) {
    bool isSelected = serialUsageType.contains(s);
    ButtonStyle style = ElevatedButton.styleFrom(
        // Toggle colors based on selection
        backgroundColor: isSelected ? Colors.blue : Colors.grey[300],
        foregroundColor: isSelected ? Colors.white : Colors.black,
    );

    switch (s) {
      case "ECG":
        return ElevatedButton(
          style: style,
          onPressed: () {
            print("ECG");
            serialUsageType = "ECG";
            startValue = 1;
            endValue = 100;
            setupFilterValues([startValue, endValue, 0]);
          },
          child: Text("ECG"));
      case "EEG":
        return ElevatedButton(
          style: style,
          onPressed: () {
            print("EEG");
            serialUsageType = "EEG";
            startValue = 0;
            endValue = 50;
            setupFilterValues([startValue, endValue, 1]);
          }, child: Text("EEG")
        );
      case "EMG":
        return ElevatedButton(
          style: style,
          onPressed: () {
            print("EMG");
            serialUsageType = "EMG";
            startValue = 70;
            endValue = 2500;
            setupFilterValues([startValue, endValue, 2]);
          }, child: Text("EMG")
        );
      case "Plant":
        return ElevatedButton(
          style: style,
          onPressed: () {
            print("Plant");
            serialUsageType = "Plant";
            startValue = 0;
            endValue = 5;
            setupFilterValues([startValue, endValue, 3]);
          }, child: Text("Plant")
        );
      case "Neuron":
        return ElevatedButton(
          style: style,
          onPressed: () {
            print("Neuron");
            serialUsageType = "Neuron";
            startValue = 70;
            endValue = _sampleRate / 2;
            setupFilterValues([startValue, endValue, 4]);
          }, child: Text("Neuron")
        );
      default:
        return Container();
    }
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
  const _AdaptiveArea({required this.child1, required this.child3, required this.child2, required this.child4, required this.notifier, required this.recordingNotifier});

  final Widget child1;
  final Widget child2;
  final Widget child3;
  final Widget child4;
  final ValueNotifier<List<double>> notifier;
  final ValueNotifier<List<int>> recordingNotifier;

  @override
  State<_AdaptiveArea> createState() => AdaptiveAreaState();
}

class AdaptiveAreaState extends State<_AdaptiveArea> {
  Debouncer debouncerScrollTimeline = Debouncer(milliseconds: 300);
  
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
            Positioned(
              left:0,
              top:0,
              child: ValueListenableBuilder<List<int>>(
                valueListenable: widget.recordingNotifier, 
                builder: (context, snapshot, _) {
                  
                  if (snapshot.isNotEmpty && snapshot[0] != 0) { // if is recording
                    // return Container();
                    Duration difference = DateTime.fromMillisecondsSinceEpoch(snapshot[1]).difference(DateTime.fromMillisecondsSinceEpoch(snapshot[0])); // Duration: 2:30:45.864000
                    String strTimeDiff = formatDuration(difference);
              
              
                    return Container(
                      color: Colors.red,
                      width: MediaQuery.of(context).size.width,
                      height: 30,
                      child: Center(
                        child: Text(strTimeDiff, style: TextStyle(color: Colors.white),),
                      )
                    );
                  } else {
                    return SizedBox();
                  }
                }),
            ),


            widget.child2,
            widget.child4,
            // Padding(
            //   padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
            //   child: widget.child2,
            // ),
            if (GraphTemplate.isLoadingFile > 0)... {
              getTimeScrubWidget(),
            },
            // if (!GraphTemplate.isPlayerPaused)... { 
              if (GraphTemplate.isLoadingFile >= 1) ...{
                // strMinTime = "00:00 000";
                Positioned(
                  left: 50,
                  bottom: 70,
                  child: Text(strMinTime,
                      textAlign: TextAlign.left, style: TextStyle(color: Colors.white)),
                ),
                Positioned(
                  right: 50,
                  bottom: 70,
                  child: Container(
                      width: 150,
                      child: Text(strMaxTime,
                          textAlign: TextAlign.right,
                          style: TextStyle(color: Colors.white))),
                )
              },

            // },
            softwareSetting.isSettingEnable
                ? Container(
                    color: Colors.black54.withOpacity(0.9),
                    // color: Colors.red,
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
  
  String formatDuration(Duration duration) {
    // Get the absolute duration to handle negative differences (time B before time A)
    final absDuration = duration.abs();
    
    // Calculate hours, minutes, and seconds from the absolute duration
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    
    // Hours can exceed 2 digits for durations longer than 24 hours
    String hours = twoDigits(absDuration.inHours);
    
    // Minutes and seconds are capped at 59 using remainder(60)
    String minutes = twoDigits(absDuration.inMinutes.remainder(60));
    String seconds = twoDigits(absDuration.inSeconds.remainder(60));
    
    // Milliseconds are the 'decimals' part
    // We take the remainder of milliseconds in a second, and pad to 3 digits.
    String milliseconds = absDuration.inMilliseconds.remainder(1000).toString().padLeft(3, "0");
    
    // Add a negative sign if the original duration was negative
    String negativeSign = duration.isNegative ? '-' : '';
    
    return '$negativeSign$hours:$minutes:$seconds $milliseconds';
  }

  getTimeScrubWidget() {
    horizontalDragXFix = MediaQuery.of(context).size.width - 100 - 20;    
    strMinTime =
        getStrMinTime(horizontalDragX, horizontalDragXFix, maxTime);    
    strMaxTime =
        getStrMinTime(horizontalDragXFix, horizontalDragXFix, maxTime);

    return Positioned(
      left: 0,
      bottom: 100,
      child: GestureDetector(
        onTapDown: (onTapDownDetails) {
          if (!GraphTemplate.isPlayerPaused) {
            return;
          }

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
          if (!GraphTemplate.isPlayerPaused) {
            return;
          }

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
            widget.notifier.value = [horizontalDragX, horizontalDragXFix];
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

  // @override
  // void didUpdateWidget(covariant _AdaptiveArea oldWidget) {
  //   super.didUpdateWidget(oldWidget);
  //   setState(() => {});
  // }
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


// https://dandiarchive.org/dandiset/000955/draft/files?location=sub-BH549&page=1