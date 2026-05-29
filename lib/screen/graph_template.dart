import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:another_xlider/models/handler.dart';
import 'package:another_xlider/models/tooltip/tooltip.dart';
import 'package:another_xlider/models/trackbar.dart';
import 'package:byb_accessory/byb_accessory.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_soloud/flutter_soloud.dart' as SoLoud;
import 'package:flutter_svg/flutter_svg.dart';
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
import 'package:spikerbox_architecture/models/audio/processed_sample_player.dart';
import 'package:spikerbox_architecture/models/processing_utils/processing_util.dart';
import 'package:spikerbox_architecture/provider/fft_status_provider.dart';
import 'package:spikerbox_architecture/provider/threshold_status_provider.dart';
import 'package:spikerbox_architecture/provider/custom_slider_provider.dart';
import 'package:spikerbox_architecture/screen/setting_page.dart';
import 'package:spikerbox_architecture/screen/spiker_box_ui.dart';
import 'package:spikerbox_architecture/widget/bybdropdown_widget.dart';
import 'package:spikerbox_architecture/widget/darkdropdown_widget.dart';
import 'package:spikerbox_architecture/widget/hump_custom_painter.dart';
import 'package:tabbed_view/tabbed_view.dart';
import 'package:wav/wav.dart';
import 'package:spikerbox_architecture/functionality/wav_file_loader.dart';
import 'package:window_manager/window_manager.dart';
import '../provider/provider_export.dart';
import '../widget/widget_export.dart';
import 'graph_page_widget/sound_wave_view.dart';
import 'package:spikerbox_architecture/models/microphone_stream/microphone_stream_check.dart';

import 'package:another_xlider/another_xlider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:vector_graphics/vector_graphics.dart';
import 'package:flutter/cupertino.dart';

import 'package:carousel_slider/carousel_slider.dart';
import '../functionality/IosConnectorDetector.dart';

class GraphTemplate extends StatefulWidget {
  static int isLoadingFile = 0;
  // isLoadingFile = 1 -> scrubbing
  // isLoadingFile = 2 -> scrubbing finished
  // isLoadingFile = 3 -> playback file
  // isLoadingFile = 4 -> playback file finished
  static bool isPlayerPaused = false;
  static Board? selectedBoard;
  static ProcessingUtil? processingUtil;
  static NWBFileUtil? nwbFileUtil;
  GraphTemplate(
      {super.key,
      required this.bitsData,
      required this.channelCount,
      required this.baudRate});

  final int bitsData;
  int channelCount = 1;
  final int baudRate;
  @override
  State<GraphTemplate> createState() => _GraphTemplateState();
}

class _GraphTemplateState extends State<GraphTemplate> {
  int defaultDeviceChannelCount = 1;
  List<List<String>> predefinedFiltersChannel = [];
  List<CarouselSliderController> carouselSliderControllerChannel = [];
  List<String> arrFilterUsageTypeChannel = [];
  String serialUsageType = "";
  List<String> filterUsageTypeChannels = [];
  List<double> bufferPos = [0, 0];
  var seekElectricalSeriesWebCompleter = Completer<Map<String, dynamic>>();

  var envelopeSizes = [];
  List<int> skipCounts = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512];
  List<int> arrCounts = [4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048];

  List<String> listOfDevices = [
    "PLANTSS;",
    "MUSCUSB1;", // "MUSCLESS;",
    "HBLEOSB;",
    "MSBPCDC;",
    "NRNSBPRO;",
    "HUMANSB;", // 5
    "MSBPCDC;",
    "NSBPCDC;",
    "HHIBOX;",
    "UNIBOX;",
    "NEURONSS;",
    "HEARTSS;"
  ];
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
  bool _isBoardTimerRunning = false;
  bool _isDeviceTimerRunning = false;
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
  final ValueNotifier<String?> _graphLineWidth = ValueNotifier("Medium");

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
    _frameDetect =
        FrameDetect(channelCount: widget.channelCount, minimumBytesToCheck: 50);
    _bitwiseUtil = BitwiseUtil(bitCount: widget.bitsData);
    _channelBytes = widget.channelCount * 2;
  }

  int dummyCount = 0;

  // bool isAudioListen = false;

  Future<void> _startPortCheck() async {
    _portCheckTimer?.cancel();
    _portCheckTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      // print("PORT CHECK TIMER forceSerialDisconnect: $forceSerialDisconnect -- isSerialDeviceFound $isSerialDeviceFound --- isOpeningFile $isOpeningFile");
      if (forceSerialDisconnect) return;
      if (isOpeningFile) return;

      if (kIsWeb) {
        if (_isDataIdentified) return;
      } else {
        if (!Platform.isIOS && _isDataIdentified) return;
      }

      // print("START PORT CHECK");
      int baudRate = context.read<ConstantProvider>().getBaudRate();
      _serialUtil.getAvailablePorts(baudRate, serialErrorCallback);
      allDevices.clear();

      List<String> filteredPorts = [];
      List<String> listOfPort =
          Provider.of<PortScanProvider>(context, listen: false).availablePorts;

      if (kIsWeb) {
        filteredPorts = _serialUtil.availablePorts;
      } else if (Platform.isMacOS) {
        filteredPorts = _serialUtil.availablePorts
            .where((port) =>
                port.contains('usbmodem') || port.contains('usbserial'))
            .toList();
      } else if (Platform.isIOS) {
        connectorType ??= await IosConnectorDetector.getConnectorType();
        if (connectorType == ConnectorType.usbC) {
          filteredPorts = _serialUtil.availablePorts
              .where((port) =>
                  port.contains('usbmodem') || port.contains('usbserial'))
              .toList();
        } else {
          if (!isMfiInitialized) {
            print(
                "BYB iOS accessory init protocol: com.backyardbrains.spikerbox");
            await BybAccessory.initWithProtocol("com.backyardbrains.spikerbox");
            _rxSub?.cancel();
            _rxSub = null;
            try {
              _rxSub = BybAccessory.rxBytesStream.listen((event) async {
                serialSubscriptionListener(event, true, listOfPort);
              }, onError: (e) {
                print('RX stream error: $e');
                forceSerialDisconnect = true;
                print("SERIAL PORT ERROR -- DISCONNECTED");
                _serialUtil.closePort();
                final provider =
                    Provider.of<GraphDataProvider>(context, listen: false);
                isMfiInitialized = false;
                _mfiMicListenerDetached = false;
                Future.delayed(Duration(milliseconds: 2500), () {
                  forceSerialDisconnect = false;
                  listenToMicrophone(1, provider);
                });
              });
            } catch (e) {
              print("Error setting up MFi RX: $e");
            }
            isMfiInitialized = true;
          }

          final accessories = await BybAccessory.getConnectedAccessories();
          print(
              "BYB IOS --- ACCESSORIES ---@--- accessories: ${accessories.isNotEmpty}");
          if (accessories.isNotEmpty) {
            if (!_mfiMicListenerDetached) {
              _mfiMicListenerDetached = true;
              try {
                // print("BYB iOS -- REMOVE MIC LISTENER");
                context
                    .read<DataStatusProvider>()
                    .setMicrophoneDataStatus(false);
                microphoneUtil.micStream.removeListener(micListener);
                if (!kIsWeb) {
                  print("microphoneUtil.micStatus?.cancel()");
                  microphoneUtil.micStatus?.cancel();
                }
                ProcessingUtil.initializeDevice.value = 0;
              } catch (e) {
                print("Error removing micListener: $e");
              }
            }
            final alreadyConnected = await BybAccessory.isConnected();
            context.read<DataStatusProvider>().setMicrophoneDataStatus(false);
            print(
                "BYB IOS --- DEVICE STATUZZZ ---@--- isMfiDeviceConnect: $isMfiDeviceConnect @@ alreadyConnected: $alreadyConnected");
            // if (isMfiDeviceConnect && isMfiDeviceConnect != alreadyConnected) {
            //   isMfiDeviceConnect = false;
            //   print(" BYB IOS - DISCONNECT 2222");
            //   if (isMfiInitialized) {
            //     isMfiInitialized = false;
            //     _mfiMicListenerDetached = false;
            //     isDeviceConnect = false;
            //     isDeviceSelected = true;
            //     final provider =
            //         Provider.of<GraphDataProvider>(context, listen: true);
            //     Future.delayed(Duration(milliseconds: 2500), () {
            //       forceSerialDisconnect = false;
            //       listenToMicrophone(1, provider);
            //     });
            //   }

            // }
            print("BYB iOS accessory alreadyConnected : $alreadyConnected");

            if (!alreadyConnected) {
              isDeviceConnect = true;
              isDeviceSelected = false;
              accessoryLabel = accessories.first;
              filteredPorts = [accessories.first];

              final isConnected =
                  await BybAccessory.connect(name: accessories.first);
              isMfiDeviceConnect = true;
              if (isConnected) {
                print("BYB iOS accessory connected: $accessoryLabel");
                // final info = await BybAccessory.getAccessoryInfo();
                // print(info);
              } else {
                print("BYB iOS accessory not connected: $accessoryLabel");
                // print('RX stream error: $e');
                // forceSerialDisconnect = true;
                // print("SERIAL PORT ERROR -- DISCONNECTED");
                // // _serialUtil.closePort();
                // try{
                //   BybAccessory.disconnect();
                // }catch(e){
                //   print("ERROR DISCONNECTING BYB ACCESSORY: $e");
                // }
                // final provider =
                //     Provider.of<GraphDataProvider>(context, listen: true);
                // isMfiInitialized = false;
                // _mfiMicListenerDetached = false;
                // Future.delayed(Duration(milliseconds: 2500), () {
                //   forceSerialDisconnect = false;
                //   listenToMicrophone(1, provider);
                // });
              }
            } else {
              isMfiDeviceConnect = true;
              print("BYB iOS accessory connected: $accessoryLabel");
              // final info = await BybAccessory.getAccessoryInfo();
              // print(info);

              print(
                  "BYB IOS --- DEVICE ALREADY CONNECTED ---@--- isMfiDeviceConnect: $isMfiDeviceConnect @@ alreadyConnected: $alreadyConnected");
            }
          } else {
            accessoryLabel = "";
            filteredPorts = [];
            // debugPrint(
            //     "BYB iOS accessory list is empty. Check UISupportedExternalAccessoryProtocols in Info.plist.");
            print(
                " BYB IOS - DISCONNECT --- isMfiDeviceConnect : $isMfiDeviceConnect");
            // if (isMfiInitialized) {
            //   isMfiInitialized = false;
            //   _mfiMicListenerDetached = false;
            //   isDeviceConnect = false;
            //   isDeviceSelected = true;
            //   final provider =
            //       Provider.of<GraphDataProvider>(context, listen: true);
            //   Future.delayed(Duration(milliseconds: 2500), () {
            //     forceSerialDisconnect = false;
            //     listenToMicrophone(1, provider);
            //   });
            // }
            if (isMfiDeviceConnect) {
              isMfiDeviceConnect = false;
              print(" BYB IOS - DISCONNECT 2222");
              if (isMfiInitialized) {
                isMfiInitialized = false;
                _mfiMicListenerDetached = false;
                isDeviceConnect = false;
                isDeviceSelected = true;
                final provider =
                    Provider.of<GraphDataProvider>(context, listen: true);
                Future.delayed(Duration(milliseconds: 2500), () {
                  forceSerialDisconnect = false;
                  listenToMicrophone(1, provider);
                });
                try {
                  BybAccessory.disconnect();
                } catch (er) {}
              }
            }
          }
          if (mounted) setState(() {});
        }
      } else {
        filteredPorts = _serialUtil.availablePorts;
        // if (Platform.isWindows) {
        //   filteredPorts = _serialUtil.availablePorts
        //       .where((port) => port.contains('COM4'))
        //       .toList();
        // }
      }

      bool isComMatch = areListsEqual(_availablePorts, filteredPorts);

      _availablePorts = filteredPorts;
      if (isOpeningFile) {
        return;
      }

      // print("SET MICROPHONE DATA STATUS: ${_availablePorts.isEmpty}");
      if (!Platform.isIOS) {
        // context
        //     .read<DataStatusProvider>()
        //     .setMicrophoneDataStatus(_availablePorts.isEmpty);
      }

      if (!isComMatch) {
        // isDeviceConnect = true;
        // isDeviceSelected = false;

        Provider.of<PortScanProvider>(context, listen: false)
            .setPortScanList(_availablePorts);

        Provider.of<ConstantProvider>(context, listen: false)
            .setBaudRate(baudRate);
        allDevices = context.read<SerialDataProvider>().getAllPortDetail;
        if (isDeviceConnect) {
          // if (blacklistSerialPortIds.contains(_availablePorts.last)) {
          //   isSerialDeviceFound = false;
          //   return;
          // }
          isSerialDeviceFound = true;
          serialPortId = _availablePorts.last;
          print("isSerialDeviceFound: $isSerialDeviceFound");
          lastEstablishingConnectionTime = DateTime.now();
          await portListOnConnect(_baudRate);
          try {
            Future.delayed(Duration(milliseconds: 2000), () async {
              final provider =
                  Provider.of<GraphDataProvider>(context, listen: false);
              _serialUtil.writeToPort(
                  bytesMessage: UsbCommand.hwTypeInquiry.cmdAsBytes(),
                  address: _availablePorts.last);
              print(
                  "isDeviceSelected: $isDeviceSelected -- isDataIdentified: $_isDataIdentified");
              // if (isDeviceSelected){
              //   context
              //       .read<DataStatusProvider>()
              //       .setMicrophoneDataStatus(_availablePorts.isEmpty);
              // }
            });
          } catch (err) {
            print("ERROR PORT LIST ON WRITE: $err");
          }
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
    print("BYB IOS LOG - INIT STATE - GRAPH TEMPLATE");
    // BybAccessory.initWithProtocol("com.backyardbrains.spikerbox").then((value) {
    //   isMfiInitialized = true;
    //   // print("BYB iOS accessory init protocol: $value");
    // });
    _deviceListStreamController =
        StreamController<List<ComDataWithBoard>>.broadcast();
    deviceListStream = _deviceListStreamController!.stream;

    Future.delayed(Duration(milliseconds: 1000), () async {
      GraphGainProvider graphGainProvider =
          Provider.of<GraphGainProvider>(context, listen: false);
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

      GraphDataProvider graphDataProvider =
          Provider.of<GraphDataProvider>(context, listen: false);
      // Remove old listener if it exists
      if (_graphDataProviderListener != null) {
        graphDataProvider.removeListener(_graphDataProviderListener!);
      }
      _graphDataProviderListener = () {
        print(
            "GraphDataProvider LISTENER : rewind ${graphDataProvider.isRewind} | forward ${graphDataProvider.isForward}");
        if (graphDataProvider.isRewind) {
          if (!isOpeningFile) return;
          _serialUtil.isOpeningFile = false;

          graphDataProvider.isRewind = false;
          AdaptiveAreaState.maxTime = loadedMaxSamples / _sampleRate;
          double scrubMaxWidth = MediaQuery.of(context).size.width - 100 - 20;
          AdaptiveAreaState.horizontalDragX = scrubMaxWidth * 0;
          scrubNotifier.value = [0, scrubMaxWidth];
          streamScrubBuilderController.add(Random().nextInt(100000));
          Future.delayed(Duration(milliseconds: 100), () async {
            callbackPlayButton(true);
          });
          setState(() {});
        } else if (graphDataProvider.isForward) {
          graphDataProvider.isForward = false;
          Provider.of<GraphResumePlayProvider>(context, listen: false)
              .setGraphResumePlay(true);
          GraphTemplate.isPlayerPaused = false;
          GraphTemplate.isLoadingFile = 0;
          try {
            periodicTimerSerial?.cancel();
          } catch (err) {
            print("ERR: $err");
          }
          // Reset processing position indices to prevent showing more than 10 seconds
          ProcessingUtil.positionIndex = 0;
          ProcessingUtil.fromSample = 0;
          ProcessingUtil.toSample = 0;

          // Reset DraggableGraph position indices
          int maxSamples =
              (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
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

              // try {
              //   _serialUtil.closePort();
              //   Future.delayed(Duration(milliseconds: 1500), () {
              //     if (context.mounted) {
              //       _availablePorts.clear();
              //     }
              //   });
              // } catch (err) {
              //   print("ERR: $err");
              // }
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
      double maxScreenSamples =
          ProcessingUtil.MAX_DISPLAY_SECONDS * sampleRateConfig;
      double arrSamplesLength = maxScreenSamples;
      double startSeekSample = 0;

      double currentSamples = percentage * loadedMaxSamples;
      if (currentSamples < maxScreenSamples) {
        startSeekSample = 0;
        arrSamplesLength = currentSamples;
      } else if (currentSamples >= maxScreenSamples) {
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
      } else {}
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
        bool? seekFlag = await GraphTemplate.nwbFileUtil?.seekElectricalSeries(
            currentLoadedFilePath,
            arrSamples,
            arrSampleCount,
            loadedConfig,
            (startSeekSample).floor(),
            endSeekSample.floor(),
            0,
            widget.channelCount - 1);
        print(
            "SCRUB NOTIFIER: WIDGET CHANNEL COUNT: $widget.channelCount | Percentage: $percentage @@@ Config: $loadedConfig ||| scrubNotifier: ${timeScrub} ${(arrSamplesLength * percentage).floor()}, ${(arrSamplesLength - startSeekSample).floor()}");
      } else {
        seekElectricalSeriesWebCompleter = Completer<Map<String, dynamic>>();
        await GraphTemplate.nwbFileUtil?.seekElectricalSeriesWeb(
            currentLoadedFilePath,
            arrSamples,
            arrSampleCount,
            loadedConfig,
            (startSeekSample).floor(),
            endSeekSample.floor(),
            0,
            widget.channelCount - 1);
        Map<String, dynamic> map =
            await seekElectricalSeriesWebCompleter.future;
        arrSamples = map['arrSamples'];
        arrSampleCount = map['arrSampleCount'];
        loadedConfig = map['loadedConfig'];
      }

      int combinedIdx = 0;
      int totalChannelCount = loadedConfig[1];
      loadedArrSamples.clear();
      loadedArrChannelCount = (Int32List(widget.channelCount));
      print(
          "Scrub : ${widget.channelCount} | arrSamples: ${arrSamples.length} | arrSampleCount: ${arrSampleCount} | combinedIdx: $combinedIdx");
      for (int i = 0; i < widget.channelCount; i++) {
        // double initialSampleCount = arrSampleCount[i].floor() / totalChannelCount;
        // double initialSampleCount = arrSampleCount[0].toDouble();
        double initialSampleCount = arrSampleCount[i].toDouble();
        if (arrSamples.length >= combinedIdx + initialSampleCount) {
          // print("LOADED ARR SAMPLES INTERUPTED: $initialSampleCount + $combinedIdx ?? ${arrSamples.length}");
          loadedArrSamples.add(Int16List(initialSampleCount.floor()));
          loadedArrSamples[i].setAll(
              0,
              arrSamples.sublist(
                  combinedIdx, combinedIdx + initialSampleCount.floor()));
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
      bool isThresholding =
          context.read<ThresholdStatusProvider>().isThresholding;
      if (isThresholding) {
        int selectedThresholdChannelIdx =
            context.read<ThresholdStatusProvider>().selectedThresholdChannel;
        int thresholdValue = context
            .read<ThresholdStatusProvider>()
            .selectedThresholdParam[selectedThresholdChannelIdx];
        processingUtil.setThreshold(thresholdValue.toDouble());
      }
    });

    // Initialize ProcessingUtil
    processingUtil = createProcessingUtil();
    if (kIsWeb) {
      processingUtil.setupDartCallbacks();
      _registerWebLivePlaybackListener();
    }
    processingUtil.postChannelCountStream =
        processingUtil.postChannelCountController.stream.asBroadcastStream();

    print("postChannelCountStream: ${processingUtil.postChannelCountStream}");
    processingUtil.postChannelCountStream?.listen((channelCount) {
      print("EXPANSION BOARD CHANNEL COUNT: $channelCount");
      widget.channelCount = channelCount;
      if (!context.read<DataStatusProvider>().isMicrophoneData) {
        unawaited(_ensureLiveMonitorPlayer(channelCount: channelCount));
      }
      context.read<ConstantProvider>().setChannelCount(channelCount);

      // Device is serial
      context.read<ChannelColorProvider>().setSerialChannelCount(channelCount);
      context.read<ChannelFilterProvider>().setSerialChannelCount(channelCount);
      ProcessingUtil.initializeDevice.value =
          ((ProcessingUtil.initializeDevice.value * 10) +
                  2 +
                  Random().nextInt(10) +
                  channelCount)
              .floor();

      customSliderBarArray.clear();
      arrFilterUsageTypeChannel.clear();
      carouselSliderControllerChannel.clear();
      for (int idxChannel = 0; idxChannel < deviceChannelCount; idxChannel++) {
        // arrFilterUsageTypeChannel.add("EMG");
        arrFilterUsageTypeChannel.add("");
        carouselSliderControllerChannel.add(CarouselSliderController());
        customSliderBarArray.add(
          CustomSliderBarButton(
            channelIdx: idxChannel,
            channelCount: widget.channelCount,
            processingUtil: processingUtil,
            isMicrophoneEnable: (bool isMicrophoneEnable) {
              context
                  .read<DataStatusProvider>()
                  .setMicrophoneDataStatus(isMicrophoneEnable);
            },
            onHighPassFilterSetup: (FilterSetup filterSetup) {
              // Keep this for backward compatibility if needed
            },
            onLowPassFilterSetup: (FilterSetup filterSetup) {
              // Keep this for backward compatibility if needed
            },
            onSampleChange: (bool isSampleDataOn) {
              context
                  .read<DataStatusProvider>()
                  .setSampleDataStatus(isSampleDataOn);
            },
            startValue: startValue,
            endValue: endValue,
            sliderValue: _sliderValue,
          ),
        );
      }
      createTabBarConfiguration(
          deviceChannelCount, context.read<ChannelFilterProvider>());
    });
    GraphTemplate.processingUtil = processingUtil;
    GraphTemplate.nwbFileUtil = createNwbFileUtil();
    if (GraphTemplate.nwbFileUtil != null) {
      GraphTemplate.nwbFileUtil!.onStartOpeningFileWebCallback =
          startOpeningFileWebCallback;
      GraphTemplate.nwbFileUtil!.onStartOpeningFileWebCallbackPlayback =
          startOpeningFileWebCallbackPlayback;
    } else {
      print("ERROR: GraphTemplate.nwbFileUtil is null");
    }

    final provider = Provider.of<GraphDataProvider>(context, listen: false);
    // Initialize stream and set provider
    _graphStream = _graphStreamController.stream.asBroadcastStream();
    provider.setStreamOfData(_graphStream);

    streamScrubBuilder =
        streamScrubBuilderController.stream.asBroadcastStream();
    streamValueBuilder =
        streamValueBuilderController.stream.asBroadcastStream();

    SchedulerBinding.instance.addPostFrameCallback((timeStamp) async {
      setSampleRate();
    });
    if (!kIsWeb) {
      _startPortCheck();
    }

    print("BYB IOS LOG - LISTEN TO MICROPHONE PROVIDER : $provider");
    listenToMicrophone(1, provider);

    filterBaseSettingsModel = FilterSetup(
        filterConfiguration:
            FilterConfiguration(cutOffFrequency: 1000, sampleRate: 10000),
        filterType: FilterType.highPassFilter,
        channelCount: channelCountBuffer,
        isFilterOn: false);
    _sampleData = GenerateSampleData.sineWaveUint14(
            samplingRate: dummySamplingRate,
            frequencies: [50, 1000],
            samplesGenerated: _sampleGeneratedCount)
        .buffer
        .asUint8List();

    // _dummyDataTimer?.cancel();
    // _dummyDataTimer =
    //     Timer.periodic(const Duration(milliseconds: timeMs), (timer) {
    //   bool dummyDataStatus = context.read<DataStatusProvider>().isSampleDataOn;
    //   if (dummyDataStatus) {
    //     _preprocessingBuffer.addBytes(_sampleData);
    //   }
    // });

    localPlugin.spawnHelperIsolate().then(
      (value) {
        localPlugin.postChannelCountStream?.listen((channelCount) {
          print("EXPANSION BOARD CHANNEL COUNT: $channelCount");
          widget.channelCount = channelCount;
          context.read<ConstantProvider>().setChannelCount(channelCount);

          // Device is serial
          context
              .read<ChannelColorProvider>()
              .setSerialChannelCount(channelCount);
          context
              .read<ChannelFilterProvider>()
              .setSerialChannelCount(channelCount);

          ProcessingUtil.initializeDevice.value =
              (ProcessingUtil.initializeDevice.value * 10) +
                  2 +
                  Random().nextInt(10) +
                  channelCount;

          customSliderBarArray.clear();
          carouselSliderControllerChannel.clear();
          arrFilterUsageTypeChannel.clear();
          for (int idxChannel = 0;
              idxChannel < deviceChannelCount;
              idxChannel++) {
            // arrFilterUsageTypeChannel.add("EMG");
            arrFilterUsageTypeChannel.add("");
            carouselSliderControllerChannel.add(CarouselSliderController());
            customSliderBarArray.add(
              CustomSliderBarButton(
                channelIdx: idxChannel,
                channelCount: widget.channelCount,
                processingUtil: processingUtil,
                isMicrophoneEnable: (bool isMicrophoneEnable) {
                  context
                      .read<DataStatusProvider>()
                      .setMicrophoneDataStatus(isMicrophoneEnable);
                },
                onHighPassFilterSetup: (FilterSetup filterSetup) {
                  // Keep this for backward compatibility if needed
                },
                onLowPassFilterSetup: (FilterSetup filterSetup) {
                  // Keep this for backward compatibility if needed
                },
                onSampleChange: (bool isSampleDataOn) {
                  context
                      .read<DataStatusProvider>()
                      .setSampleDataStatus(isSampleDataOn);
                },
                startValue: startValue,
                endValue: endValue,
                sliderValue: _sliderValue,
              ),
            );
          }
          createTabBarConfiguration(
              deviceChannelCount, context.read<ChannelFilterProvider>());
        });
        localPlugin.postFilterStream?.listen((serialData) {
          bool isAudioListen =
              context.read<DataStatusProvider>().isMicrophoneData;
          if (!isAudioListen) {
            if (kIsWeb) {
              provider.inputListener(Uint8List(0));
            }
          }
          // _preGraphBuffer.addBytes(event);
        });
        localPlugin.postDisplayStream?.listen((event) {
          bool isAudioListen =
              context.read<DataStatusProvider>().isMicrophoneData;
          if (isAudioListen) {
            provider.inputListener(event);
          }
          // print("POST DISPLAY STREAM: $event | ${event.length}");
        });
      },
    );
    _preprocessingBuffer = BufferHandler(
      chunkReadSize: 2000,
      onDataAvailable: (Uint8List listBytes) async {
        return;
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

    _frameDetect =
        FrameDetect(channelCount: widget.channelCount, minimumBytesToCheck: 50);
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
              _graphStreamController
                  .add(ChannelUtil.dropEveryOtherTwoBytes(dataFromBuffer));
              break;
          }
        }
      },
    );

    final providerScroll =
        Provider.of<GraphDataProvider>(context, listen: false);
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
            double prevStartElementIdx = screenPositionToElementPosition(
                SoundWaveView.dragDetails!.position.dx,
                _sampleRate,
                ProcessingUtil.positionIndex,
                TimeCalculateWidget.prevDisplayTimeMsLabel * 0.001,
                TimeCalculateWidget.prevWidthOfScale,
                MediaQuery.of(context).size.width,
                bufferPos);
            double startElementIdx = screenPositionToElementPosition(
                SoundWaveView.dragDetails!.position.dx,
                _sampleRate,
                ProcessingUtil.positionIndex,
                TimeCalculateWidget.displayTimeMsLabel * 0.001,
                TimeCalculateWidget.widthOfScale,
                MediaQuery.of(context).size.width,
                bufferPos);
            print(
                "DIFFERENCES = $prevStartElementIdx - $startElementIdx = ${prevStartElementIdx - startElementIdx} | ${ProcessingUtil.positionIndex}");
            // print("LABELS: ${DraggableGraph.eventMarkersPosition} ${DraggableGraph.eventMarkersLabels} ||| ${ProcessingUtil.eventLabels.sublist(0, ProcessingUtil.currentEventMarkers)} - Sublist: ${ProcessingUtil.eventPosition.sublist(0, ProcessingUtil.currentEventMarkers)}");
// main.dart.js:25928 DIFFERENCES = NaN - 524989.0625 = NaN | 0
            if (prevStartElementIdx.isNaN) {
              bufferPaddingLeft = bufferPaddingLeft;
            } else {
              bufferPaddingLeft =
                  bufferPaddingLeft - (prevStartElementIdx - startElementIdx);
            }
            if (displayTimeMs == 10000) {
              bufferPaddingLeft = 0;
            }
          }
          // if (bufferPaddingLeft < 0) {
          //   bufferPaddingLeft = 0;
          // }
        } else {
          print(
              "LABELS: ${DraggableGraph.eventMarkersPosition} ${DraggableGraph.eventMarkersLabels} ||| ${ProcessingUtil.eventLabels.sublist(0, ProcessingUtil.currentEventMarkers)} - Sublist: ${ProcessingUtil.eventPosition.sublist(0, ProcessingUtil.currentEventMarkers)}");
          bufferPaddingLeft = 0;
        }
      });
    });
    print("BYB IOS LOG END INIT STATE");

    setState(() {});
  }

  @override
  void dispose() {
    print("GraphTemplate dispose: cleaning up resources...");
    if (kIsWeb) {
      ProcessingUtil.webLivePlaybackListener = null;
    }

    // Cancel all timers
    _portCheckTimer?.cancel();
    _dummyDataTimer?.cancel();
    periodicTimerSerial?.cancel();
    timerPlaybackLoadedFile?.cancel();

    // Remove listeners
    if (_graphDataProviderListener != null) {
      try {
        final graphDataProvider =
            Provider.of<GraphDataProvider>(context, listen: false);
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
    _cancelSerialStaleWatchdog();
    _resetSerialIngestPipeline();
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
  final List<int> _baudRate = [500000, 230400, 222222];
  List<int> _channelCount = [1, 2];

  int deviceChannelCount = 1;

  String portName = "";
  bool isMfiDeviceConnect = false;
  bool isDeviceConnect = true;
  bool isDeviceSelected = false;
  bool isSettingEnable = false;

  List<ComDataWithBoard>? listOfBoard;

  String foundDevices = "";

  int deviceType = -1;

  String configTitle = "Channels";
  bool isDrawerOpened = false;

  @override
  Widget build(BuildContext widgetContext) {
    bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
    String openedFilePath = "";
    if (currentLoadedFilePath.isNotEmpty) {
      if (kIsWeb) {
        openedFilePath = currentLoadedFilePath.split("/").last;
      } else {
        if (Platform.isWindows) {
          openedFilePath = currentLoadedFilePath.split("\\").last;
        } else {
          openedFilePath = currentLoadedFilePath.split("/").last;
        }
      }
    }

    IconData drawerIconData = CupertinoIcons.chevron_up;
    if (isDrawerOpened) {
      drawerIconData = CupertinoIcons.chevron_down;
    }

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
              child3: Container(
                decoration: BoxDecoration(
                  color: Color(0xFF222222),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(0, 10, 0, 10),
                      child: Row(children: [
                        ElevatedButton(
                          onPressed: () {
                            if (configTitle == "Channel Settings") {
                              configTitle = "Channels";
                              isDetailConfiguration = false;
                              customizeDetailChannelIdx = 0;

                              createTabBarConfiguration(
                                  widget.channelCount,
                                  Provider.of<ChannelFilterProvider>(context,
                                      listen: false));
                            } else {
                              context
                                  .read<SoftwareConfigProvider>()
                                  .settingStatus(false);
                            }
                            setState(() {});
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2C2C2C),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: const CircleBorder(),
                            padding: EdgeInsets
                                .zero, // Clear padding to center the icon perfectly
                          ).copyWith(
                            side: WidgetStateProperty.resolveWith<BorderSide>(
                                (states) {
                              if (states.contains(WidgetState.hovered)) {
                                return const BorderSide(
                                    color: Colors.blue, width: 1.5);
                              }
                              return const BorderSide(
                                  color: Colors.transparent);
                            }),
                          ),
                          child: const Icon(Icons.chevron_left, size: 24),
                        ),
                        SizedBox(
                          width: 10,
                        ),
                        Text(
                          configTitle,
                          style: TextStyle(
                              fontSize: 24,
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                      ]),
                    ),
                    if (isDetailConfiguration) ...[
                      Container(
                        margin: EdgeInsets.fromLTRB(10, 0, 10, 0),
                        decoration: BoxDecoration(
                          color: Color(0xFF222222),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(children: [
                          _mutingSpeakers(),
                          SizedBox(height: 10),
                          // customSliderBarArray[customizeDetailChannelIdx],
                          const SizedBox(
                            height: 10,
                          ),
                          _channelColorSettings(customizeDetailChannelIdx),
                          // ElevatedButton(
                          //   style: ElevatedButton.styleFrom(
                          //     backgroundColor: SoftwareColors.kButtonBackGroundColor,
                          //     shape: RoundedRectangleBorder(
                          //       borderRadius: BorderRadius.circular(12),
                          //     ),
                          //   ),
                          //   child: Text(
                          //     "SAVE CHANGES",
                          //     style: TextStyle(color: Colors.white),
                          //   ),
                          //   onPressed: () {
                          //     // customSliderBarArray[customizeDetailChannelIdx].startValue = 0;
                          //     // customSliderBarArray[customizeDetailChannelIdx].endValue = (_sampleRate / 2);
                          //     // Provider.of<CustomRangeSliderProvider>(context, listen: false)
                          //     //   .setStartValue(customSliderBarArray[customizeDetailChannelIdx].startValue, customizeDetailChannelIdx);
                          //     // Provider.of<CustomRangeSliderProvider>(context, listen: false)
                          //     //   .setEndValue(customSliderBarArray[customizeDetailChannelIdx].endValue, customizeDetailChannelIdx);
                          //     // setState(() {});
                          //   },
                          // ),
                        ]),
                      ),
                    ] else ...[
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
                          child: Stack(children: [
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              // bottom:0,
                              child: SizedBox(
                                height: serialUsageType == "Custom" ? 340 : 220,
                                child: TabbedViewTheme(
                                  data: channelTabTheme!,
                                  child: TabbedView(
                                    controller: _channelTabController!,
                                    contentBuilder: (context, index) {
                                      return ClipRRect(
                                        borderRadius: BorderRadius.all(
                                            Radius.circular(16)),
                                        clipBehavior: Clip.antiAlias,
                                        child: Container(
                                            color: Color(0xFF2e2e2e),
                                            child: Center(
                                                child: getTabbedViewChildren(
                                                    index))),
                                      );
                                    },
                                    tabCloseInterceptor: (tabIndex, tabData) {
                                      return false;
                                    },
                                    tabSelectInterceptor: (int channelIdx) {
                                      // Keep tab stable while drawer is open, but
                                      // allow tapping widgets inside current tab.
                                      if (isDrawerOpened) {
                                        return false;
                                      }
                                      selectedTabIdx = channelIdx;
                                      serialUsageType =
                                          arrFilterUsageTypeChannel[channelIdx];
                                      print(
                                          "arrFilterUsageTypeChannel: $arrFilterUsageTypeChannel --- $serialUsageType");
                                      // createTabBarConfiguration(deviceChannelCount, context.read<ChannelFilterProvider>());
                                      setState(() {});
                                      return true;
                                    },
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: MenuTheme(
                                  data: MenuThemeData(
                                    style: MenuStyle(
                                      backgroundColor: WidgetStateProperty.all(
                                          Color(0xFF222222)),
                                      shape: WidgetStateProperty.all(
                                        RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                      ),
                                    ),
                                  ),
                                  child: MenuAnchor(
                                    builder: (context, controller, child) {
                                      return GestureDetector(
                                        onTap: () {
                                          if (controller.isOpen) {
                                            controller.close();
                                          } else {
                                            controller.open();
                                          }
                                        },
                                        child: Icon(Icons.more_horiz,
                                            color: Color(0xFF707070)),
                                      );
                                    },
                                    menuChildren: [
                                      MenuItemButton(
                                        onPressed: () {
                                          isDetailConfiguration = true;
                                          configTitle = "Channel Settings";
                                          context
                                              .read<SoftwareConfigProvider>()
                                              .settingStatus(true);

                                          setState(() {});
                                        },
                                        child: Row(children: [
                                          Icon(Icons.settings_outlined,
                                              color: Colors.white),
                                          SizedBox(width: 10),
                                          Text("Channel Settings")
                                        ]),
                                        style: ButtonStyle(
                                          foregroundColor:
                                              WidgetStateProperty.all(Colors
                                                  .white), // Text & Icon color
                                          // textStyle: WidgetStateProperty.all(
                                          //   const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                          // ),
                                        ),
                                      ),
/*                                        
                                        MenuItemButton(
                                          onPressed: () => print('Action 2'),
                                          child: Row(
                                            children: [
                                              Icon(Icons.add_circle_outline, color: Colors.white),
                                              SizedBox(width: 10),
                                              Text("Add new channel"),
                                            ]
                                          ),
                                          style: ButtonStyle(
                                            foregroundColor: WidgetStateProperty.all(Colors.white), // Text & Icon color
                                          ),
                                        ),
                                        Divider(),
                                        MenuItemButton(
                                          onPressed: () => print('Action 2'),
                                          child: Row(
                                            children: [
                                              Icon(CupertinoIcons.trash, color: Colors.white),
                                              SizedBox(width: 10),
                                              Text("Remove channel"),
                                            ]
                                          ),
                                          style: ButtonStyle(
                                            foregroundColor: WidgetStateProperty.all(Colors.white), // Text & Icon color
                                          ),
                                        ),
*/
                                    ],
                                  )),
                            ),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 50,
                                      height: 30,
                                      child: GestureDetector(
                                        onTap: () {
                                          isDrawerOpened = !isDrawerOpened;
                                          setState(() {});
                                        },
                                        child: Container(
                                            decoration: BoxDecoration(
                                              color: Color(0x14D9D9D9),
                                              borderRadius: BorderRadius.only(
                                                topLeft: Radius.circular(16),
                                                bottomLeft: Radius.circular(0),
                                                topRight: Radius.circular(
                                                    16), // Keeps the right side flat
                                                bottomRight: Radius.circular(0),
                                              ),
                                            ),
                                            // color: Color(0xFF2e2e2e),
                                            child: Center(
                                                child: Icon(drawerIconData,
                                                    color: Colors.white))),
                                      ),
                                    ),

                                    // Container(
                                    //   // padding: EdgeInsets.all(10),
                                    //   decoration: BoxDecoration(
                                    //     // color: Color(0xFF2e2e2e),
                                    //     // borderRadius: BorderRadius.circular(16),
                                    //   ),
                                    //   child: Column(
                                    //     mainAxisSize:
                                    //         MainAxisSize.min, // Vital for scrolling
                                    //     children: [
                                    //       FilterProcessWidget(isMicrophoneEnable:
                                    //           (bool isMicrophoneEnable) {
                                    //         context
                                    //             .read<DataStatusProvider>()
                                    //             .setMicrophoneDataStatus(
                                    //                 isMicrophoneEnable);
                                    //       }, onHighPassFilterSetup:
                                    //           (FilterSetup filterSetup) {
                                    //         localPlugin
                                    //             .initHighPassFilters(filterSetup);
                                    //       }, onLowPassFilterSetup:
                                    //           (FilterSetup filterSetup) {
                                    //         localPlugin
                                    //             .initLowPassFilters(filterSetup);
                                    //       }, onSampleChange: (bool isSampleDataOn) {
                                    //         context
                                    //             .read<DataStatusProvider>()
                                    //             .setSampleDataStatus(isSampleDataOn);
                                    //         // _toGenerateDummyData =
                                    //         //     isSampleDataOn;
                                    //       }),
                                    //     ],
                                    //   ),
                                    // ),
                                    if (isDrawerOpened) ...[
                                      Container(
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          color: Color(0x14D9D9D9),
                                          borderRadius: BorderRadius.only(
                                            topLeft: Radius.circular(16),
                                            bottomLeft: Radius.circular(0),
                                            topRight: Radius.circular(
                                                16), // Keeps the right side flat
                                            bottomRight: Radius.circular(0),
                                          ),
                                        ),
                                        child: NotchPassFilterWidget(
                                            sampleRateParam:
                                                _sampleRate.toDouble(),
                                            onTapNotchFrequency:
                                                (notchFilterSettings) async {
                                              notchFilterSettings
                                                  .filterConfiguration
                                                  .sampleRate = _sampleRate;
                                              try {
                                                if (notchFilterSettings
                                                    .isFilterOn) {
                                                  final cutOff =
                                                      notchFilterSettings
                                                          .filterConfiguration
                                                          .cutOffFrequency;
                                                  if (cutOff == 50 ||
                                                      cutOff == 60) {
                                                    await processingUtil
                                                        .setNotchFilter(
                                                            cutOff.toDouble());
                                                  }
                                                } else {
                                                  await processingUtil
                                                      .setNotchFilter(-1);
                                                }
                                              } catch (e, st) {
                                                debugPrint(
                                                    'setNotchFilter failed: $e\n$st');
                                              }
                                              if (!context.mounted) return;
                                              context
                                                  .read<DataStatusProvider>()
                                                  .setNotchPassFilterSetting(
                                                      notchFilterSettings);
                                            }),
                                      ),
                                      Divider(
                                        height: 1,
                                        thickness: 1,
                                        color: Color(0x70707070),
                                      ),
                                      Container(
                                          decoration: BoxDecoration(
                                            color: Color(0x14D9D9D9),
                                            borderRadius: BorderRadius.only(
                                              topLeft: Radius.circular(0),
                                              bottomLeft: Radius.circular(0),
                                              topRight: Radius.circular(
                                                  0), // Keeps the right side flat
                                              bottomRight: Radius.circular(0),
                                            ),
                                          ),
                                          child: Row(
                                              mainAxisSize: MainAxisSize.max,
                                              children: [
                                                Padding(
                                                  padding: EdgeInsets.fromLTRB(
                                                      10, 10, 0, 10),
                                                  child: Icon(
                                                      CupertinoIcons
                                                          .speedometer,
                                                      color: Colors.white),
                                                ),
                                                SizedBox(width: 10),
                                                Text("Channel width",
                                                    style: TextStyle(
                                                        color: Colors.white)),
                                                SizedBox(width: 10),
                                                Expanded(
                                                  child: Container(
                                                    height: 30,
                                                    padding: const EdgeInsets
                                                        .fromLTRB(0, 0, 10, 0),
                                                    // child: Text("address", style: SoftwareTextStyle().kWtMediumTextStyle),
                                                    child: BybDropdown(
                                                        kIsWeb: kIsWeb,
                                                        availableItems: [
                                                          "Thin",
                                                          "Medium",
                                                          "Wide"
                                                        ],
                                                        onItemSelected:
                                                            (String str) {
                                                          print("STR : $str");
                                                          if (str.toLowerCase() ==
                                                              "thin") {
                                                            SpikerBoxUi
                                                                    .defaultStrokeWidth =
                                                                0.75;
                                                          } else if (str
                                                                  .toLowerCase() ==
                                                              "medium") {
                                                            SpikerBoxUi
                                                                .defaultStrokeWidth = 1;
                                                          } else if (str
                                                                  .toLowerCase() ==
                                                              "wide") {
                                                            SpikerBoxUi
                                                                .defaultStrokeWidth = 2;
                                                          }
                                                          _graphLineWidth
                                                              .value = str;
                                                        },
                                                        valueListenable:
                                                            _graphLineWidth),
                                                  ),
                                                ),
                                              ])),
                                      Divider(
                                        height: 1,
                                        thickness: 1,
                                        color: Color(0x70707070),
                                      ),
                                      Container(
                                        decoration: BoxDecoration(
                                          color: Color(0x14D9D9D9),
                                          borderRadius: BorderRadius.only(
                                            topLeft: Radius.circular(0),
                                            bottomLeft: Radius.circular(0),
                                            topRight: Radius.circular(
                                                0), // Keeps the right side flat
                                            bottomRight: Radius.circular(0),
                                          ),
                                        ),
                                        child: Consumer<PortScanProvider>(
                                            builder:
                                                (context, portList, snapshot) {
                                          return _PortsArea(
                                            deviceName: _deviceName,
                                            availablePorts:
                                                portList.availablePorts,
                                            onTriggerDisconnect:
                                                onTriggerDisconnect,
                                            onReceive: (String add) async {},
                                            onWrite: (String add) async {
                                              // serialWebButtonPressed();
                                            },
                                          );
                                        }),
                                      ),
                                    ],

                                    // 5. Footer Row
                                    Container(
                                      margin: const EdgeInsets.fromLTRB(
                                          0, 0, 0, 10),
                                      padding: const EdgeInsets.fromLTRB(
                                          5, 10, 10, 10),
                                      decoration: BoxDecoration(
                                        // borderRadius: BorderRadius.circular(16),
                                        // color: Color(0xFF2e2e2e),
                                        color: Color(0x14D9D9D9),
                                        borderRadius: BorderRadius.only(
                                          topLeft: isDrawerOpened
                                              ? Radius.circular(0)
                                              : Radius.circular(16),
                                          bottomLeft: Radius.circular(16),
                                          topRight: isDrawerOpened
                                              ? Radius.circular(0)
                                              : Radius.circular(16),
                                          bottomRight: Radius.circular(16),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.max,
                                        children: [
                                          // 1. The Custom Switch
                                          // Switch(
                                          //   value: isDarkMode,
                                          //   activeColor: Colors.white,
                                          //   activeTrackColor: Color(
                                          //       0xFFFF7A5C), // The orange/coral color in your image
                                          //   onChanged: (value) {
                                          //     setState(() {
                                          //       isDarkMode = value;
                                          //     });
                                          //   },
                                          // ),
                                          // SizedBox(width: 8),

                                          // 2. The Main Label
                                          // Text(
                                          //   'Dark Mode',
                                          //   style: TextStyle(
                                          //     color: Colors.white,
                                          //     fontWeight: FontWeight.bold,
                                          //     fontSize: 14,
                                          //   ),
                                          // ),

                                          // 3. Spacing to push version info to the right
                                          Spacer(),

                                          // 4. App Version Info
                                          Icon(Icons.info_outline,
                                              color: Colors.grey, size: 16),
                                          SizedBox(width: 6),
                                          Text(
                                            'SpikeRecorder App ver. 2.1.10',
                                            style: TextStyle(
                                              color: Colors.grey,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ]),

                              ////////asdasd
                            ),
                          ]),
                        ),
                        // child: TabbedView(
                        //   controller: _channelTabController!,
                        //   tabCloseInterceptor: (tabIndex, tabData) {
                        //     return false;
                        //   },
                        // ),
                      ),
                    ],
                  ],
                ),
              ),
              child4: !kIsWeb && Platform.isAndroid && isThresholdingButton
                  ? Positioned(
                      left: 10,
                      top: 80,
                      child: SafeArea(
                        child: Row(
                          children: generateThresholdSlider(false),
                        ),
                      ),
                    )
                  : SizedBox(),
              child2: Positioned(
                left: 0,
                top: 0,
                child: Container(
                  padding: kIsWeb
                      ? const EdgeInsets.symmetric(horizontal: 10, vertical: 15)
                      : Platform.isAndroid || Platform.isIOS
                          ? const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 65)
                          : const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 15),
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
                              isRecording == 1
                                  ? SizedBox()
                                  : SpikerBoxButton(
                                      onTapButton: () async {
                                        context
                                            .read<SoftwareConfigProvider>()
                                            .settingStatus(true);
                                      },
                                      // iconData: Icons.settings),
                                      iconData: const IconData(0xe90a,
                                          fontFamily: "IcomoonIcons")),
                              const SizedBox(
                                width: 10,
                              ),
                              // Text(accessoryLabel ?? "-@-", style: TextStyle(color: Colors.red)),
                              // Text("BLANKK", style: TextStyle(color: Colors.red)),

                              serialWebButton(),
                              // SpikerBoxButton(
                              //     onTapButton: () async {}, iconData: Icons.graphic_eq),
                              // const SizedBox(
                              //   width: 10,
                              // ),
                              isRecording == 1
                                  ? SizedBox()
                                  : SpikerBoxButton(
                                      onTapButton: () {
                                        isThresholdingButton =
                                            !isThresholdingButton;
                                        thresholdSliderValue = 1;

                                        print(
                                            "initThreshold : ${_sampleRate}, $deviceChannelCount === deviceChannelCount :$deviceChannelCount @@@ isThresholdingButton :$isThresholdingButton  ");
                                        if (isThresholdingButton) {
                                          processingUtil.initThreshold(
                                              deviceChannelCount,
                                              _sampleRate,
                                              MediaQuery.of(context)
                                                  .size
                                                  .width);
                                          processingUtil
                                              .setAveragedSampleCount(1);
                                          processingUtil.setThreshold(525);
                                          processingUtil
                                              .setIsThresholding(true);
                                        } else {
                                          processingUtil
                                              .setIsThresholding(false);
                                        }

                                        context
                                            .read<ThresholdStatusProvider>()
                                            .setThresholdStatus(
                                                isThresholdingButton);
                                        context
                                            .read<ThresholdStatusProvider>()
                                            .setThresholdChannel(0);

                                        setState(() {});
                                      },
                                      iconColor: isThresholdingButton
                                          ? Colors.yellow
                                          : Colors.white,
                                      // iconData: Icons.graphic_eq_outlined,
                                      iconData: const IconData(0xe90b,
                                          fontFamily: "IcomoonIcons"),
                                    ),
                              const SizedBox(
                                width: 20,
                              ),
                              if (isThresholdingButton) ...{
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
                              // CONNECT LIST USB SERIAL WEB
                              /*
                              StreamBuilder<List<ComDataWithBoard>>(
                                  stream: deviceListStream,
                                  builder: (context, snapshot) {
                                    // print("snapshot.hasData: ${snapshot.hasData}");
                                    if (snapshot.hasData) {
                                      print("snapshot.data: ${snapshot.data}");
                                      listOfBoard = snapshot.data!;
                                      if (listOfBoard?.length == 0) {
                                        return SpikerBoxButton(
                                            onTapButton: () async {
                                              print("USB ICON CLICKED");
                                              forceSerialDisconnect = true;
                                              initMessageIdentifier();

                                              await Future.delayed(
                                                  Duration(milliseconds: 1000));

                                              int baudRate = context
                                                  .read<ConstantProvider>()
                                                  .getBaudRate();
                                              await _serialUtil
                                                  .getAvailablePorts(baudRate,
                                                      serialErrorCallback);
                                              allDevices.clear();

                                              List<String> filteredPorts;
                                              if (kIsWeb) {
                                                filteredPorts =
                                                    _serialUtil.availablePorts;
                                              } else if (Platform.isMacOS) {
                                                filteredPorts = _serialUtil
                                                    .availablePorts
                                                    .where((port) =>
                                                        port.contains(
                                                            'usbmodem') ||
                                                        port.contains(
                                                            'usbserial'))
                                                    .toList();
                                              } else {
                                                filteredPorts =
                                                    _serialUtil.availablePorts;
                                              }

                                              bool isComMatch = areListsEqual(
                                                  _availablePorts,
                                                  filteredPorts);

                                              _availablePorts = filteredPorts;

                                              context
                                                  .read<DataStatusProvider>()
                                                  .setMicrophoneDataStatus(
                                                      _availablePorts.isEmpty);
                                              print(
                                                  "isDeviceConnect : $isDeviceConnect -- ${_availablePorts.isEmpty} -- ${context.read<DataStatusProvider>().isMicrophoneData} -- forceSerialDisconnect: $forceSerialDisconnect ${listOfBoard?.length} isComMatch: $isComMatch");

                                              // if (!isComMatch) {
                                              Provider.of<PortScanProvider>(
                                                      context,
                                                      listen: false)
                                                  .setPortScanList(
                                                      _availablePorts);
                                              Provider.of<ConstantProvider>(
                                                      context,
                                                      listen: false)
                                                  .setBaudRate(baudRate);
                                              allDevices = context
                                                  .read<SerialDataProvider>()
                                                  .getAllPortDetail;
                                              if (isDeviceConnect) {
                                                isSerialDeviceFound = true;
                                                lastEstablishingConnectionTime = DateTime.now();
                                                await portListOnConnect();
                                              }

                                              forceSerialDisconnect = true;
                                              // }
                                            },
                                            iconData: Icons.usb);
                                      }

                                      return SizedBox(
                                        height: 50,
                                        child: ListView.builder(
                                            padding: EdgeInsets.zero,
                                            scrollDirection: Axis.horizontal,
                                            shrinkWrap: true,
                                            itemCount: listOfBoard?.length,
                                            itemBuilder: (context, index) {
                                              return SpikerBoxButton(
                                                  onTapButton: () {
                                                    print("DISCONNECT USB");
                                                    forceSerialDisconnect =
                                                        !forceSerialDisconnect;
                                                    _serialUtil.closePort();
                                                    Future.delayed(
                                                        Duration(
                                                            milliseconds: 1500),
                                                        () {
                                                      if (context.mounted) {
                                                        _availablePorts.clear();
                                                        context
                                                            .read<
                                                                DataStatusProvider>()
                                                            .setMicrophoneDataStatus(
                                                                _availablePorts
                                                                    .isEmpty);
                                                        final provider = Provider
                                                            .of<GraphDataProvider>(
                                                                context,
                                                                listen: false);
                                                        listenToMicrophone(
                                                            1, provider);
                                                      }
                                                      // final provider = Provider.of<GraphDataProvider>(context, listen: false);
                                                    });
                                                  },
                                                  iconData: Icons.usb);
                                            }),
                                      );
                                    } else {
                                      return Container();
                                    }
                                  })
                              */
                            ],
                          ),
                          Row(
                            children: [
                              if (isRecording != 1) ...{
                                SpikerBoxButton(
                                  onTapButton: () async {
                                    if (kIsWeb) {
                                      // print("START OPENING FILE WEB");
                                      startOpeningFileWeb("", 0, 1);
                                      // startOpeningFile(result.files.single.path!);
                                    } else {
                                      FilePickerResult? result =
                                          await FilePicker.platform.pickFiles();
                                      if (result != null) {
                                        startOpeningFile(
                                            result.files.single.path!);
                                      }
                                    }
                                    // }, iconData: Icons.menu)
                                  },
                                  iconData: const IconData(0xe909,
                                      fontFamily: "IcomoonIcons"),
                                )
                              },
                            ],
                          )
                        ],
                      ),
                      // Text("isOpeningFile: $isOpeningFile && isRecording: $isRecording"),
                      if (isOpeningFile) ...[
                        BottomButtons(
                          pauseButton: (bool isPlay) async {
                            print(
                                "PAUSE BUTTON CALLED: $isPlay --- isOpeningFile: $isOpeningFile");
                            if (!isOpeningFile) {
                              Provider.of<GraphResumePlayProvider>(context,
                                      listen: false)
                                  .setGraphResumePlay(isPlay);
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
                      if (!isOpeningFile) ...[
                        Center(
                          child: SpikerBoxButton(
                            onTapButton: () async {
                              // print("STATUS RECORDING: $isRecording | Sample Rate: $_sampleRate");
                              if (isRecording == 0) {
                                if (kIsWeb) {
                                } else if (Platform.isIOS) {
                                  _channelCount = [1];
                                }
                                print(
                                    "!!!INIT NWB FILE, $_sampleRate, ${_channelCount.length}");

                                bool isAudioListen = context
                                    .read<DataStatusProvider>()
                                    .isMicrophoneData;
                                visibleSignalsList = context
                                    .read<ChannelColorProvider>()
                                    .getVisibleChannel();
                                visibleChannelCount = context
                                    .read<ChannelColorProvider>()
                                    .getVisibleChannelCount();

                                if (kIsWeb) {
                                  // await GraphTemplate.nwbFileUtil
                                  //     ?.recordNewFileLocation();
                                  // int counterTimerCancel = 0;
                                  // Timer.periodic(
                                  //     Duration(seconds: 1),
                                  //     (timer) async {
                                  // counterTimerCancel++;
                                  // print(
                                  //     "GraphTemplate.nwbFileUtil?.recordedNwbFilePath: ${GraphTemplate.nwbFileUtil?.recordedNwbFilePath}");
                                  String strTemp = GraphTemplate
                                          .nwbFileUtil?.recordedNwbFilePath ??
                                      "";
                                  // if (strTemp.length! > 3) {
                                  if (1 == 1) {
                                    // timer.cancel();
                                    if (isAudioListen) {
                                      recordedFilePath = await GraphTemplate
                                          .nwbFileUtil
                                          ?.processingInit(
                                              _sampleRate,
                                              widget.channelCount,
                                              "Audio|||",
                                              "SpikeRecorder Systems",
                                              visibleSignalsList,
                                              visibleChannelCount);
                                    } else {
                                      recordedFilePath = await GraphTemplate
                                          .nwbFileUtil
                                          ?.processingInit(
                                              _sampleRate,
                                              widget.channelCount,
                                              "SpikeRecorder Device|||",
                                              "SpikeRecorder Systems@@@${GraphTemplate.selectedBoard?.uniqueName}",
                                              visibleSignalsList,
                                              visibleChannelCount);
                                    }
                                    bool isPlay = true;
                                    Provider.of<GraphResumePlayProvider>(
                                            context,
                                            listen: false)
                                        .setGraphResumePlay(isPlay);
                                    _toPauseGraph = isPlay;
                                    GraphTemplate.isPlayerPaused = !isPlay;
                                    _pendingPlayback = false;

                                    Future.delayed(Duration(milliseconds: 1000),
                                        () {
                                      isRecording = 1;
                                      context
                                          .read<ChannelColorProvider>()
                                          .setIsRecording(1);

                                      recordingStartTime =
                                          DateTime.now().millisecondsSinceEpoch;

                                      recordingNotifier.value = [
                                        recordingStartTime,
                                        recordingStartTime
                                      ];
                                      setState(() {});
                                    });
                                  } else if (GraphTemplate
                                          .nwbFileUtil?.recordedNwbFilePath ==
                                      "--") {
                                    // GraphTemplate.nwbFileUtil
                                    //     ?.recordedNwbFilePath = "";
                                    // print("NWB FILE PATH");
                                    // counterTimerCancel = 0;
                                    // isOpeningFile = false;
                                    // timer.cancel();
                                  }
                                  // });
                                } else {
                                  if (isAudioListen) {
                                    recordedFilePath = await GraphTemplate
                                        .nwbFileUtil
                                        ?.processingInit(
                                            _sampleRate,
                                            widget.channelCount,
                                            "Audio|||",
                                            "SpikeRecorder Systems",
                                            visibleSignalsList,
                                            visibleChannelCount);
                                  } else {
                                    recordedFilePath = await GraphTemplate
                                        .nwbFileUtil
                                        ?.processingInit(
                                            _sampleRate,
                                            widget.channelCount,
                                            "SpikeRecorder Device|||",
                                            "SpikeRecorder Systems",
                                            visibleSignalsList,
                                            visibleChannelCount);
                                  }
                                  Future.delayed(Duration(milliseconds: 1000),
                                      () {
                                    isRecording = 1;
                                    context
                                        .read<ChannelColorProvider>()
                                        .setIsRecording(1);
                                    recordingStartTime =
                                        DateTime.now().millisecondsSinceEpoch;

                                    recordingNotifier.value = [
                                      recordingStartTime,
                                      recordingStartTime
                                    ];
                                    setState(() {});
                                  });
                                }
                                // isRecording = 1;
                              } else {
                                resetRecordingState(widgetContext);
                                setState(() {});
                              }
                            },
                            iconData: Icons.fiber_manual_record,
                            iconColor:
                                isRecording == 1 ? Colors.red : Colors.white,
                          ),
                        ),
                      ],
                      // isRecording != 0
                      //     ? SizedBox()
                      //     : !isOpeningFile ? SizedBox() :
                    ],
                  ),
                ),
              ),
              childOverlay: !isOpeningFile
                  ? SizedBox()
                  : Positioned(
                      bottom: 35,
                      right: 10,
                      child: Container(
                          margin: kIsWeb
                              ? const EdgeInsets.fromLTRB(0, 0, 0, 0)
                              : Platform.isAndroid || Platform.isIOS
                                  ? const EdgeInsets.fromLTRB(0, 110, 0, 0)
                                  : const EdgeInsets.fromLTRB(0, 0, 0, 0),
                          child: SizedBox(
                            child: Container(
                                alignment: Alignment.center,
                                // margin: EdgeInsets.only(top: 65),
                                padding: EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 4),
                                decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(16)),
                                child: Text(openedFilePath,
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 10))),
                          )),
                    ),
            );
          }),
      floatingActionButton: null,
    );
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

  List<int> serialBuffer = [];
  Future<void> portListOnConnect(List<int> _rawbaudRate) async {
    try {
      List<int> _baudRate = List<int>.from(_rawbaudRate);
      DataStatusProvider dataStatus = context.read<DataStatusProvider>();
      List<String> listOfPort =
          Provider.of<PortScanProvider>(context, listen: false).availablePorts;
      // int baudRate = context.read<ConstantProvider>().getBaudRate();
      if (listOfPort.isEmpty) {
        return;
      }

      // for (int baudRate in _baudRate) {
      if (_baudRate.isEmpty) {
        return;
      }
      int baudRate = _baudRate.removeAt(0);
      {
        print(
            "portListOnConnect listOfPort: $listOfPort --- baudRate: $baudRate");
        try {
          getData =
              (await _serialUtil.openPortToListen(listOfPort.last, baudRate))
                  ?.asBroadcastStream();
          try {
            _serialUtil.writeToPort(
                bytesMessage: UsbCommand.hwTypeInquiry.cmdAsBytes());
          } catch (e) {
            print("Error $baudRate: $e");
          }
        } catch (err) {
          print("Error $baudRate: $err");
        }
      }

      // Only proceed if connection was successful
      if (getData == null) {
        print("Failed to connect to port: ${listOfPort.last}");
        dataStatus.setDeviceDataStatus(false);
        return;
      }

      bool dummyDataStatus = dataStatus.isSampleDataOn;
      bool isAudioListen = dataStatus.isMicrophoneData;
      print("portListOnConnect setDeviceDataStatus: true");
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
        deviceStatusStreamSubscription =
            _serialUtil.deviceStatusStreamListener().listen((event) {
          print("DEVICE STATUS STREAM: $event");
          if (event == "android.hardware.usb.action.USB_DEVICE_DETACHED") {
            forceSerialDisconnect = true;
            bool isMicrophoneActive =
                context.read<DataStatusProvider>().isMicrophoneData;
            // if haven't switch to serial port, do nothing
            print(
                "SERIAL PORT ERROR -- DISCONNECTED -- isMicrophoneActive: $isMicrophoneActive");
            if (isMicrophoneActive) return;

            serialDataSubscription?.cancel();
            deviceStatusStreamSubscription?.cancel();
            _serialUtil.closePort();
            Future.delayed(Duration(milliseconds: 2500), () {
              forceSerialDisconnect = false;
              _isSerialWebButtonEnabled = false;
              isDeviceConnect = false;
              isDeviceSelected = false;
              if (boardTimer != null) {
                boardTimer?.cancel();
                boardTimer = null;
              }
              if (deviceTimer != null) {
                deviceTimer?.cancel();
                deviceTimer = null;
              }

              _isDataIdentified = false;
              streamScrubBuilderController.add(Random().nextInt(100000));
              listenToMicrophone(1, provider);
            });
          }
        });
      }
      serialDataSubscription?.cancel();
      serialDataSubscription = getData?.listen((event) async {
        serialSubscriptionListener(event, false, listOfPort);
        return;
        isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
        // print("IS AUDIO LISTEN | Writing to port b:; : ${isAudioListen}");
        if (!isAudioListen) {
          final provider =
              Provider.of<GraphDataProvider>(context, listen: false);
          int drawSurfaceWidth = MediaQuery.of(context).size.width.toInt();
          if (isDeviceConnect) {
            if (isRecording == 1) return;
            print(
                "Writing to port b:; : ${UsbCommand.hwTypeInquiry.cmdAsBytes()} ${DateTime.now().millisecondsSinceEpoch}");
            Future.delayed(Duration(milliseconds: 1000), () {
              print("DELAYED: ${DateTime.now().millisecondsSinceEpoch}");
              _serialUtil.writeToPort(
                  bytesMessage: UsbCommand.hwTypeInquiry.cmdAsBytes(),
                  address: listOfPort.last);
              // isDeviceConnect = false;
            });
            isDeviceConnect = false;
          }
          if (_isDataIdentified) {
            serialNativeDataSubscription(event, isAudioListen);
          } else {
            if (!isDeviceConnect && !isDeviceSelected) {
              // print("_preEscapeSequenceBuffer ADDBYTES EVENT: ${event} | isDeviceConnect: ${isDeviceConnect} | isDeviceSelected: ${isDeviceSelected}");
              _preEscapeSequenceBuffer.addBytes(event);
            }
            if (isDeviceSelected) {
              // !isDeviceConnect &&
              _isDataIdentified = true;
              if (!_isBoardTimerRunning) {
                _isBoardTimerRunning = true;
                if (boardTimer != null) {
                  boardTimer?.cancel();
                  boardTimer = null;
                }
                boardTimer = Timer.periodic(Duration(seconds: 3), (timer) {
                  if (isRecording == 1) return;
                  if (GraphTemplate.selectedBoard != null &&
                      GraphTemplate.selectedBoard!.expansionBoards != null &&
                      GraphTemplate.selectedBoard!.expansionBoards!.isEmpty)
                    return;

                  _isBoardTimerRunning = false;
                  print("Writing to port board:;");
                  Uint8List commandBytes =
                      Uint8List.fromList(utf8.encode("board:;"));
                  _serialUtil.writeToPort(
                      bytesMessage: commandBytes,
                      address: _availablePorts.last);
                });
              }
              if (!GraphTemplate.isPlayerPaused) {
                _enqueueSerialIngest(
                  event,
                  provider,
                  drawSurfaceWidth,
                  paintFromZero: true,
                );
              } else {
                // await processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider);
                // int fromSample = (-bufferPaddingLeft).toInt();
                // int toSample = (fromSample + displayTimeMs * 0.001 * _sampleRate).toInt();
                int maxSamples =
                    (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
                int toSample = (maxSamples + bufferPaddingLeft).toInt();
                toSample = min(maxSamples, toSample);
                int fromSample =
                    (toSample - displayTimeMs * 0.001 * _sampleRate).toInt();
                DraggableGraph.startPositionIdx = fromSample;
                DraggableGraph.endPositionIdx = toSample;
                // DEBUG STEVE
                // return;

                // processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, fromSample, toSample );
                await processingUtil.processDisplaySerialData(
                    displayTimeMs.toInt(),
                    deviceType,
                    drawSurfaceWidth,
                    provider,
                    fromSample,
                    toSample);

                provider.inputListener(Uint8List(0));
              }
            } else {
              if (!_isDeviceTimerRunning) {
                _isDeviceTimerRunning = true;
                if (deviceTimer != null) {
                  deviceTimer?.cancel();
                  deviceTimer = null;
                }
                deviceTimer = Timer.periodic(Duration(seconds: 7), (timer) {
                  if (isRecording == 1) return;
                  print("Writing to port device:;");
                  _serialUtil.writeToPort(
                      bytesMessage: UsbCommand.hwTypeInquiry.cmdAsBytes(),
                      address: _availablePorts.last);
                });
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
        //     Uint8List? firstFrameData = _frameDetect.addData(0event);

        //     if (firstFrameData != null) {
        //       _preEscapeSequenceBuffer.addBytes(firstFrameData);
        //       _isDataIdentified = true;
        //     }
        //   }
        // }
      }, onError: (error) {
        // if (error is SerialPortError) {
        forceSerialDisconnect = true;
        bool isMicrophoneActive =
            context.read<DataStatusProvider>().isMicrophoneData;
        // if haven't switch to serial port, do nothing
        print(
            "SERIAL PORT ERROR -- DISCONNECTED -- isMicrophoneActive: $isMicrophoneActive");
        if (isMicrophoneActive) return;

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
      // check if SERIAL DATA SUBSCRIPTION FOUND ANY DEVICES
      Future.delayed(Duration(milliseconds: 5500)).then((v) {
        if (_isDataIdentified && isDeviceSelected) {
        } else {
          portListOnConnect(_baudRate);
        }
      });
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

  StreamSubscription<Uint8List>? microphoneSubscription;
  StreamSubscription<Uint8List>? serialDataSubscription;
  StreamSubscription<String?>? deviceStatusStreamSubscription;

  SendPort? processSerialSendPort;
  ReceivePort? processSerialReceivePort;
  SendPort? processSerialDisplaySendPort;
  ReceivePort? processSerialDisplayReceivePort;

  int totalSampleCount = 0;
  int sampleCountToDisplay = 8;

  /// Serialized UART ingest: one [processSerialData] at a time, coalesce backlog.
  final List<Uint8List> _serialIngestQueue = [];
  bool _serialIngestDraining = false;

  /// Caps graph repaints (~60 Hz) while [sampleCountToDisplay] gates sample batching.
  DateTime? _lastSerialDisplayAt;
  bool _serialDisplayDeferred = false;
  bool _serialGraphPaintInFlight = false;
  static const Duration _minSerialDisplayInterval = Duration(milliseconds: 16);

  /// [rollingWindow] vs [rollingFromZero] display window for live serial.
  bool _serialPaintFromZero = false;

  /// Rolling window meter for serial RX (see [serialSubscriptionListener]).
  final Stopwatch _serialRxThroughputStopwatch = Stopwatch();
  int _serialRxBytesInWindow = 0;
  static const Duration _serialRxThroughputLogInterval = Duration(seconds: 1);

  /// On-wire ADC rate for SpikerBox serial (not [_sampleRate], which follows mic/UI).
  static const int _serialRxBaselineSampleRate = 10000;

  double bufferPaddingLeft = 0;

  Board? selectedBoard;

  bool isThresholdingButton = false;
  bool isFftButton = false;

  bool isChoosingThresholdType = false;

  TextEditingController thresholdValueController = TextEditingController();

  List<String> listMenuOptions = [
    "Ev",
    "E1",
    "E2",
    "E3",
    "E4",
    "E5",
    "E6",
    "E7",
    "E8",
    "E9"
  ];
  List<String> listMenuLabels = [
    "Signal",
    "E1",
    "E2",
    "E3",
    "E4",
    "E5",
    "E6",
    "E7",
    "E8",
    "E9",
    "Ev"
  ];

  String eventThresholdTriggeredType = "Signal";
  List<TabData> channelTabs = [];

  Path _drawFolderTabPath(Size size) {
    var path = Path();
    double curveWidth = 15.0; // Adjust for more or less slant

    path.moveTo(0, size.height);
    // Bottom-left to top-left curve
    path.quadraticBezierTo(curveWidth / 2, size.height, curveWidth, 0);
    path.lineTo(size.width - curveWidth, 0);
    // Top-right to bottom-right curve
    path.quadraticBezierTo(
        size.width - (curveWidth / 2), size.height, size.width, size.height);
    path.close();

    return path;
  }

  void listenToMicrophone(channelCount, provider) async {
    print("listenToMicrophone");
    stopCurrentPlaying();
    _registerWebLivePlaybackListener();
    _deviceName.value = "";
    predefinedFiltersChannel = [
      ["EMG", "ECG", "EEG", "Custom"]
    ];
    defaultDeviceChannelCount = 1;
    _isSerialWebButtonEnabled = false;

    // Prevent multiple simultaneous calls
    print(
        "isListeningToMicrophone : $_isListeningToMicrophone --- $customSliderBarArray");
    if (_isListeningToMicrophone) {
      print(
          "listenToMicrophone already in progress, waiting for completion...");
      if (_listenToMicrophoneCompleter != null) {
        try {
          await _listenToMicrophoneCompleter!.future;
        } catch (error) {
          // Another in-flight initialization failed; avoid bubbling an uncaught
          // async error from the waiter path and let the next call retry setup.
          print("Previous listenToMicrophone failed: $error");
        }
      }
      return;
    }

    localPlugin.currentExpansionBoardString = "";
    visibleSignalsList = [1];
    visibleChannelCount = 1;
    carouselSliderControllerChannel.clear();
    carouselSliderControllerChannel.add(CarouselSliderController());
    customSliderBarArray = [
      CustomSliderBarButton(
        channelIdx: 0,
        channelCount: widget.channelCount,
        processingUtil: processingUtil,
        isMicrophoneEnable: (bool isMicrophoneEnable) {
          context
              .read<DataStatusProvider>()
              .setMicrophoneDataStatus(isMicrophoneEnable);
        },
        onHighPassFilterSetup: (FilterSetup filterSetup) {
          // Keep this for backward compatibility if needed
        },
        onLowPassFilterSetup: (FilterSetup filterSetup) {
          // Keep this for backward compatibility if needed
        },
        onSampleChange: (bool isSampleDataOn) {
          context
              .read<DataStatusProvider>()
              .setSampleDataStatus(isSampleDataOn);
        },
        startValue: startValue,
        endValue: endValue,
        sliderValue: _sliderValue,
      ),
    ];
    print(
        "isListeningToMicrophone222 : $_isListeningToMicrophone --- $customSliderBarArray");
    filterUsageTypeChannels.clear();
    // filterUsageTypeChannels.add("EMG");
    filterUsageTypeChannels.add("");
    arrFilterUsageTypeChannel.clear();
    // arrFilterUsageTypeChannel.add("EMG");
    arrFilterUsageTypeChannel.add("");
    carouselSliderControllerChannel.clear();
    carouselSliderControllerChannel.add(CarouselSliderController());

    // serialUsageType = "EMG";
    serialUsageType = "";

    createTabBarConfiguration(channelCount, provider);

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

      try {
        widget.channelCount = channelCount;
        Provider.of<ConstantProvider>(context, listen: false)
            .setChannelCount(channelCount);
        Provider.of<SampleRateProvider>(context, listen: false)
            .setSampleRate(microphoneUtil.sampleRate.floor());

        microphoneUtil.micStream.removeListener(micListener);
        microphoneUtil.micStream = ValueNotifier(Uint8List(0));
        context.read<DataStatusProvider>().setMicrophoneDataStatus(true);
        print("LISTEN TO MICROPHONE setMicrophoneDataStatus");
      } catch (err) {
        print("er remove listener");
        print(err);
      }

      await Future.delayed(const Duration(microseconds: 10));

      print("_messageIdentifier.messageState");
      print(_messageIdentifier.messageState);
      // Initialize both utils

      await Future.wait([microphoneUtil.init()]);

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
      print("listenToMicrophone2, $_sampleRate");

      double drawSurfaceWidth = MediaQuery.of(context).size.width;
      await processingUtil.initializeMicrophone(
          channelCount, _sampleRate, drawSurfaceWidth);
      context.read<ChannelColorProvider>().setAudioChannelCount(channelCount);
      context.read<ChannelFilterProvider>().setAudioChannelCount(channelCount);

      // Set band filter
      await processingUtil.setBandFilter(-1, -1, -1);

      print("listenToMicrophone5");
      await _ensureLiveMonitorPlayer(channelCount: channelCount);

      microphoneUtil.micStream.addListener(micListener);
      isDeviceConnect = true;
      isDeviceSelected = false;
      ProcessingUtil.initializeDevice.value = 0;

      _listenToMicrophoneCompleter!.complete();
    } catch (error) {
      print("Error in listenToMicrophone: $error");
      if (_listenToMicrophoneCompleter != null &&
          !_listenToMicrophoneCompleter!.isCompleted) {
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
  bool _isStreamEnded = false; // Flag to track if streams are ended

  double startSeekSampleIdx = 0;
  double endSeekSampleIdx = 0;

  ValueNotifier<List<double>> scrubNotifier = ValueNotifier([]);
  ValueNotifier<List<int>> recordingNotifier = ValueNotifier([0, 0]);

  SoLoud.SoLoud? soloud;
  List<SoLoud.AudioSource?> loadedFileStreams = [];

  List<SoLoud.SoundHandle?> loadedSoundHandles = [];

  /// Live monitor: plays tails of [ProcessingUtil.processMicrophoneData] via SoLoud.
  ProcessedSamplePlayer? _processedSamplePlayer;

  /// Reused inside [micListener] so we process once and play before graph work.
  List<Int16List>? _liveMicProcessedCache;

  int? _liveMonitorSampleRate;
  int? _liveMonitorChannelCount;

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

  /// Broadcasts [listOfBoard] updates; must stay non-null after [initState] so hot-plug / MFi can refresh UI.
  StreamController<List<ComDataWithBoard>>? _deviceListStreamController;

  void _emitConnectedDeviceBoardList() {
    if (_deviceListStreamController == null ||
        _deviceListStreamController!.isClosed ||
        !mounted) {
      return;
    }
    if (connectedDevices.isEmpty) {
      _deviceListStreamController!.add(<ComDataWithBoard>[]);
      return;
    }
    allDevices = context.read<SerialDataProvider>().getAllPortDetail;
    SetUpFunctionality().getAllDeviceList().then((value) {
      if (!mounted ||
          _deviceListStreamController == null ||
          _deviceListStreamController!.isClosed) {
        return;
      }
      final List<Board> allBoards = value.boards ?? [];
      final List<Board> connectedBoards = allBoards
          .where((board) => connectedDevices.contains(board.uniqueName))
          .toList();
      final List<ComDataWithBoard> deviceDataWithCom =
          createComDataWithBoardList(connectedBoards, allDevices);
      _deviceListStreamController!.add(deviceDataWithCom);
    });
  }

  void micListener() {
    // print("miCLISTENER DATA | TIME: ${DateTime.now().millisecondsSinceEpoch} |||| ${microphoneUtil.micStream.value.sublist(0,10)}");
    int channelCount = 1;
    int selectedThresholdChannel = 0;
    final provider = Provider.of<GraphDataProvider>(context, listen: false);

    bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
    _liveMicProcessedCache = null;

    // Live monitor: process + enqueue before graph/NWB/FFT work to minimize latency.
    if (isAudioListen &&
        _shouldRunLiveMonitor() &&
        !isThresholdingButton &&
        microphoneUtil.micStream.value.isNotEmpty &&
        !isSpeakerChannelMuted[0]) {
      final micChunk = Uint8List.fromList(microphoneUtil.micStream.value);
      if (!kIsWeb) {
        _liveMicProcessedCache = processingUtil.processMicrophoneData(micChunk);
        _processedSamplePlayer?.enqueueProcessedChunk(_liveMicProcessedCache!);
      }
    }
    // print("isAUDIO LISTEN: $isAudioListen GraphTemplate.isLoadingFile: ${GraphTemplate.isLoadingFile}");
    if (isAudioListen) {
      if (GraphTemplate.isLoadingFile == 2 ||
          GraphTemplate.isLoadingFile == 4) {
        // print("GraphTemplate.isLoadingFile: ${GraphTemplate.isLoadingFile}");
        int drawSurfaceWidth = MediaQuery.of(context).size.width.toInt();
        // int maxSamples = (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
        // int maxDisplaySamples = (displayTimeMs * 0.001 * _sampleRate).floor();
        // DraggableGraph.startPositionIdx = maxSamples - maxDisplaySamples;
        // DraggableGraph.endPositionIdx = maxSamples;
        // processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, 0, maxDisplaySamples );

        int maxSamples =
            (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
        // int maxSamples = loadedMaxSamples;
        int toSample = (maxSamples + bufferPaddingLeft).toInt();
        toSample = min(maxSamples, toSample);
        int fromSample =
            (toSample - displayTimeMs * 0.001 * _sampleRate).toInt();
        if (isThresholdingButton) {
          // print("Don't Draw last result for thresholding");
          // if (!kIsWeb) {
          return;
          // }
        }
        processingUtil.prepareDisplayMicrophoneData(
            [Int16List(0)],
            drawSurfaceWidth,
            channelCount,
            displayTimeMs,
            provider,
            fromSample,
            toSample);
        // print("RANGE MASK : ${DraggableGraph.startPositionIdx} -- ${DraggableGraph.endPositionIdx} || ${maxDisplaySamples} || ${maxSamples} ${_sampleRate}");
      } else if (GraphTemplate.isLoadingFile == 1) {
        // print("PROCESS MICROPHONE ISLOADINGFILE 1");
        GraphTemplate.isLoadingFile = 2;
        // List<Int16List> tempData = processingUtil.processMicrophoneData(loadedArrSamples.sublist(0, loadedArrChannelCount[0]).buffer.asUint8List());
        // loadedArrSamples[0].fillRange(0, loadedArrSamples[0].length, 5000);
        List<Int16List> tempData = processingUtil
            .processMicrophoneData(loadedArrSamples[0].buffer.asUint8List());
        // List<Int16List> tempData = processingUtil.processMicrophoneData(Uint8List(0));
        microphoneUtil.micStream.value = Uint8List(0);
        if (isThresholdingButton) {
          return;
        }
      } else {
        if (GraphTemplate.isLoadingFile == 3) {
          // print("PROCESS MICROPHONE ISLOADINGFILE 3");
          GraphTemplate.isLoadingFile = 4;
          // print("PROCESS MICROPHONE DATA LOADED 3: ${GraphTemplate.isLoadingFile}");
          List<Int16List> tempData = processingUtil
              .processMicrophoneData(microphoneUtil.micStream.value);
        } else if (!GraphTemplate.isPlayerPaused) {
          if (isThresholdingButton) {
            if (kIsWeb) {
              processingUtil
                  .processMicrophoneData(microphoneUtil.micStream.value);
            } else {
              List<Int16List> tempData = processingUtil
                  .processMicrophoneData(microphoneUtil.micStream.value);
              tempData.add(Int16List.fromList(tempData[0]));
              Int32List samplesCount = Int32List(tempData.length);

              // int counterLen = 0;
              int channelIdx = 0;
              Int16List flattenedList =
                  Int16List.fromList(tempData.expand((list) {
                samplesCount[channelIdx] = tempData[channelIdx].length;
                // counterLen += tempData[channelIdx].length;
                channelIdx++;
                return list;
              }).toList());

              if (isRecording == 1) {
                // print("GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 1, 0) 11 -- $isRecording ${samplesCount}");
                // STEVE
                if (!kIsWeb) {
                  GraphTemplate.nwbFileUtil?.addElectricalSeries(
                      flattenedList, samplesCount, 0, 1, 0);
                }
                recordingNotifier.value = [
                  recordingStartTime,
                  DateTime.now().millisecondsSinceEpoch
                ];

                // GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 2, 0);
              } else if (isRecording == 2) {
                isRecording = 0;
                // STEVE
                // print("END RECORDING!!! GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 1, 1)");
                // print("GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 2, 1)");
                if (!kIsWeb) {
                  GraphTemplate.nwbFileUtil?.addElectricalSeries(
                      flattenedList, samplesCount, 0, 1, 1);
                }
                recordingNotifier.value = [
                  recordingStartTime,
                  DateTime.now().millisecondsSinceEpoch
                ];
              }
              bool isAverageSamples = true;
              arr = processingUtil.processThresholdData(
                  tempData,
                  tempData.length,
                  MediaQuery.of(context).size.width.floor(),
                  selectedThresholdChannel,
                  isAverageSamples);
            }
          } else {
            List<Int16List> tempData = _liveMicProcessedCache ??
                processingUtil.processMicrophoneData(
                    Uint8List.fromList(microphoneUtil.micStream.value));
            _liveMicProcessedCache = null;
            tempData.add(Int16List.fromList(tempData[0]));
            // print("PROCESS MICROPHONE DATA LOADED 4 : ${GraphTemplate.isLoadingFile} || TEMPDATA - $tempData");
            Int32List samplesCount =
                Int32List(tempData.length * widget.channelCount);

            int counterLen = 0;
            int channelIdx = 0;
            Int16List flattenedList =
                Int16List.fromList(tempData.expand((list) {
              samplesCount[channelIdx] = tempData[channelIdx].length;
              counterLen += tempData[channelIdx].length;
              channelIdx++;
              return list;
            }).toList());

            if (isRecording == 1) {
              // print("GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 2, 0) 22 -- $isRecording");
              // STEVE
              if (!kIsWeb) {
                GraphTemplate.nwbFileUtil
                    ?.addElectricalSeries(flattenedList, samplesCount, 0, 1, 0);
              }
              recordingNotifier.value = [
                recordingStartTime,
                DateTime.now().millisecondsSinceEpoch
              ];
              // GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 2, 0);
            } else if (isRecording == 2) {
              isRecording = 0;
              print(
                  "ENDING RECORDING GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 2, 1)");
              // STEVE
              if (!kIsWeb) {
                GraphTemplate.nwbFileUtil
                    ?.addElectricalSeries(flattenedList, samplesCount, 0, 1, 1);
              }
              recordingNotifier.value = [
                recordingStartTime,
                DateTime.now().millisecondsSinceEpoch
              ];
              // GraphTemplate.nwbFileUtil?.addElectricalSeries(flattenedList, samplesCount, 0, 2, 1);
            }

            // if (isFftButton) {
            if (!kIsWeb) {
              int windowCount = ((10.0 * 128) / (512 * 0.01).floor()).floor();
              int windowSize = (FFT_30HZ_LENGTH * FFT_WINDOW_TIME_LENGTH);
              List<int> inSampleCounts = [];
              // print("KISWEB inSampleCounts: ${tempData[0].length}");
              for (var data in tempData) {
                inSampleCounts.add(data.length);
              }
              processingUtil.processFftMicrophoneData(tempData, [windowCount],
                  [windowSize], inSampleCounts, channelCount);
            }
            // }
          }
        }
        // _preGraphBuffer.addBytes(event);

        // if (drawIdx == 3) {
        int drawSurfaceWidth = MediaQuery.of(context).size.width.toInt() *
            MediaQuery.of(context).devicePixelRatio.toInt();
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
            int maxSamples =
                (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
            int toSample = maxSamples - (gap / 2).floor();
            int fromSample = toSample - arr[0] + (gap).floor();
            // print("GAP THRESHOLD: $gap - Start : $fromSample -- (${(gap/2).floor()}) - END: $toSample -- ${ (arr[0]-gap/2).floor() }");
            DraggableGraph.startPositionIdx = fromSample;
            DraggableGraph.endPositionIdx = toSample;
            processingUtil.prepareDisplayMicrophoneData(
                [Int16List(0)],
                drawSurfaceWidth,
                channelCount,
                displayTimeMs,
                provider,
                fromSample,
                toSample);
            // processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, (0 + gap/2).floor(), (arr[0] - gap/2).floor() );
          } else {
            // DraggableGraph.startPositionIdx = 0;
            // DraggableGraph.endPositionIdx = (displayTimeMs*0.001 * microphoneUtil.sampleRate).floor();
            int maxSamples =
                (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
            int maxDisplaySamples =
                (displayTimeMs * 0.001 * _sampleRate).floor();
            DraggableGraph.startPositionIdx = maxSamples - maxDisplaySamples;
            DraggableGraph.endPositionIdx = maxSamples;
            // print("RANGE MASK :");
            // print("RANGE MASK : ${DraggableGraph.startPositionIdx} -- ${DraggableGraph.endPositionIdx} || ${maxDisplaySamples} || ${maxSamples}");
            // print("PROCESS MICROPHONE DATA LOADED 3: PREPARE DISPLAY MICROPHONE DATA");
            processingUtil.prepareDisplayMicrophoneData(
                [Int16List(0)],
                drawSurfaceWidth,
                channelCount,
                displayTimeMs,
                provider,
                0,
                maxDisplaySamples);
            if (isFftButton) {
              Size screenSize = MediaQuery.of(context).size;
              // int windowCount = processingUtil.window_count[0];
              // double windowSize = processingUtil.window_size[0].toDouble();
              // processingUtil.prepareForFftDrawing(windowCount, windowSize.floor(), screenSize.width.toInt(), (screenSize.height * FFT_WIDGET_HEIGHT).toInt());
              int maxWindowCount =
                  ((10.0 * 128) / (512 * 0.01).floor()).floor();
              int windowCount = maxWindowCount;
              int drawEndIndex = DraggableGraph.endPositionIdx;
              int drawStartIndex = DraggableGraph.startPositionIdx;
              // double drawWidthMax = maxDisplaySamples.toDouble();
              // int targetWindowCount = (maxWindowCount * (drawEndIndex - drawStartIndex) / drawWidthMax).floor();
              int targetWindowCount = (maxWindowCount *
                      (drawEndIndex - drawStartIndex) /
                      maxSamples)
                  .floor();

              // double windowSize = MediaQuery.of(context).size.height * FFT_WIDGET_HEIGHT;
              int windowSize = (FFT_30HZ_LENGTH * FFT_WINDOW_TIME_LENGTH);
              // print("CALCULATION1: (maxWindowCount * (drawEndIndex - drawStartIndex) / drawWidthMax).floor()");
              // print("CALCULATION2: (${drawEndIndex - drawStartIndex})");
              // print("CALCULATION3: ($maxWindowCount * ($drawEndIndex - $drawStartIndex) / $maxSamples).floor() = $targetWindowCount :: $maxSamples");
              // print("INDEX: $drawStartIndex -- $drawEndIndex : $drawWidthMax $targetWindowCount vs $windowCount");
              // jint maxWindowCount = env->GetArrayLength(in);
              // jint windowCount = static_cast<jint>(maxWindowCount * (drawEndIndex - drawStartIndex) /
              //                                      drawWidthMax);
              processingUtil.prepareForFftDrawing(
                  windowCount,
                  windowSize,
                  targetWindowCount,
                  screenSize.width,
                  (screenSize.height * FFT_WIDGET_HEIGHT));
            }
          }
        } else {
          double startElementIdx = 0.0;

          // if (ProcessingUtil.positionIndex > 0) {
          if (SoundWaveView.dragDetails != null) {
            if (kIsWeb) {
              arr = [
                processingUtil.thresholdingArraylength,
                processingUtil.thresholdingArraylength
              ];
            }

            // int level = calculateLevel(displayTimeMs, _sampleRate.toDouble(), drawSurfaceWidth.toDouble(), arrCounts, 0);
            // double divider = ;
            // int fromSample = (ProcessingUtil.positionIndex - displayTimeMs * 0.001 * _sampleRate - bufferPaddingLeft).toInt();
            // int fromSample = (-bufferPaddingLeft).toInt();
            // int toSample = (fromSample + displayTimeMs * 0.001 * _sampleRate).toInt();
            int maxSamples =
                (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
            // print("bufferPaddingLeft : $bufferPaddingLeft | max samples: $maxSamples");
            int toSample = (maxSamples + bufferPaddingLeft).toInt();
            toSample = min(maxSamples, toSample);
            int fromSample =
                (toSample - displayTimeMs * 0.001 * _sampleRate).toInt();
            // int toSample = (displayTimeMs * 0.001 * _sampleRate).toInt();
            // print("fromSample - toSample : $fromSample _ $toSample  ${bufferPaddingLeft} ${displayTimeMs * 0.001 * _sampleRate} ${bufferPos[1]}");
            if (isThresholdingButton) {
              // processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, 0, arr[0] );

              double displayTimeDivision = (displayTimeMs / 10000);
              double gap = (arr[0] * (1 - displayTimeDivision));
              int maxSamples =
                  (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
              int toSample = maxSamples - (gap / 2).floor();
              int fromSample = toSample - arr[0] + (gap).floor();

              DraggableGraph.startPositionIdx = fromSample;
              DraggableGraph.endPositionIdx = toSample;
              processingUtil.prepareDisplayMicrophoneData(
                  [Int16List(0)],
                  drawSurfaceWidth,
                  channelCount,
                  displayTimeMs,
                  provider,
                  fromSample,
                  toSample);
              // processingUtil.prepareDisplayMicrophoneThresholdData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, arr[0], (0 + gap/2).floor(), (arr[0] - gap/2).floor() );
              // processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, (0 + gap/2).floor(), (arr[0] - gap/2).floor() );
            } else {
              DraggableGraph.startPositionIdx = fromSample;
              DraggableGraph.endPositionIdx = toSample;
              processingUtil.prepareDisplayMicrophoneData(
                  [Int16List(0)],
                  drawSurfaceWidth,
                  channelCount,
                  displayTimeMs,
                  provider,
                  fromSample,
                  toSample);
            }
          } else {
            // processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, 0, 10 * _sampleRate );
            if (isThresholdingButton) {
              DraggableGraph.startPositionIdx = 0;
              DraggableGraph.endPositionIdx = arr[0];
              processingUtil.prepareDisplayMicrophoneData(
                  [Int16List(0)],
                  drawSurfaceWidth,
                  channelCount,
                  displayTimeMs,
                  provider,
                  0,
                  arr[0]);
            } else {}
          }

          if (isFftButton) {
            Size screenSize = MediaQuery.of(context).size;
            int maxWindowCount = ((10.0 * 128) / (512 * 0.01).floor()).floor();
            int maxSamples =
                (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();

            int windowCount = maxWindowCount;
            int drawEndIndex = DraggableGraph.endPositionIdx;
            int drawStartIndex = DraggableGraph.startPositionIdx;
            int targetWindowCount =
                (maxWindowCount * (drawEndIndex - drawStartIndex) / maxSamples)
                    .floor();

            int windowSize = (FFT_30HZ_LENGTH * FFT_WINDOW_TIME_LENGTH);
            print(
                "prepareForFftDrawing wc: $windowCount ws:$windowSize twc:$targetWindowCount ${screenSize.width} ${screenSize.height * FFT_WIDGET_HEIGHT}");
            processingUtil.prepareForFftDrawing(
                windowCount,
                windowSize,
                targetWindowCount,
                screenSize.width,
                (screenSize.height * FFT_WIDGET_HEIGHT));
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
    Isolate isolate = await Isolate.spawn(
        processingUtil.processSerialDataIsolate,
        processSerialReceivePort?.sendPort);

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
    Isolate isolate = await Isolate.spawn(
        processingUtil.processDisplaySerialDataIsolate,
        processSerialDisplayReceivePort?.sendPort);

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
      ChannelColorProvider provider, bool isAudio, int curChannelIdx) {
    final colors = isAudio ? provider.audioColors : provider.serialColors;
    String title = isAudio ? 'Audio Channel Colors' : 'Serial Channel Colors';

    List<Widget> children = [];
    for (int idx = 0; idx < colors.length; idx++) {
      if (idx != curChannelIdx) {
        children.add(SizedBox.shrink());
        continue;
      }
      children.add(
          // ...List.generate(colors.length, (idx) {
          // return
          Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {},
          hoverColor: Color(0xFF4c4c4c),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            margin: EdgeInsets.fromLTRB(1, 1, 1, 1),
            padding: EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Color(0xFF2e2e2e),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                // Icon(IconData(0xe90e, fontFamily: "IcomoonIcons"), color: Colors.white),
                // Container(
                //   width: 20,
                //   height: 20,
                //   decoration: BoxDecoration(
                //     color: Colors.orange,
                //     shape: BoxShape.circle,
                //   ),
                //   child: Center(child: Text('${idx + 1}', style: TextStyle(color: Colors.white)))
                // ),
                // SizedBox(width: 10),
                Icon(Icons.palette_outlined, size: 20, color: Colors.white),
                // SvgPicture.asset(
                //   'assets/icons/config_board.svg',
                //   width: 20,
                //   height: 20,
                // ),
                SizedBox(width: 10),
                Text('Channel Color',
                    style: SoftwareTextStyle().kWtMediumTextStyle),
                const SizedBox(width: 8),
                Container(
                  height: 30,
                  margin: EdgeInsets.fromLTRB(0, 5, 0, 5),
                  padding: EdgeInsets.fromLTRB(3, 2, 3, 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.blueGrey),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<Color>(
                      padding: EdgeInsets.fromLTRB(0, 0, 0, 0),
                      icon: Icon(IconData(0xe90e, fontFamily: "IcomoonIcons"),
                          size: 20, color: Colors.grey),
                      value: colors[idx],
                      dropdownColor: SoftwareColors.kDropDownBackGroundColor,
                      items: availableColors
                          .map((c) => DropdownMenuItem(
                                value: c,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    color: c,
                                    border: Border.all(color: c, width: 1),
                                  ),
                                  width: 40,
                                  height: 20,
                                ),
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
                  ),
                ),
                SizedBox(width: 10),
                // ElevatedButton(
                //   onPressed: () {

                //     double startValue = customSliderBarArray[idx].startValue;
                //     Provider.of<CustomRangeSliderProvider>(context, listen: false)
                //         .setStartValue(startValue);
                //     print("startValue CUSTOMIZED: $startValue");
                //     double endValue = customSliderBarArray[idx].endValue;
                //     Provider.of<CustomRangeSliderProvider>(context, listen: false)
                //         .setEndValue(endValue);
                //     print("endValue CUSTOMIZED: $startValue");

                //     isDetailConfiguration = !isDetailConfiguration;
                //     customizeDetailChannelIdx = idx;
                //     configTitle = "Channel Settings";

                //     setState(() {});
                //   },
                //   style: ElevatedButton.styleFrom(
                //     backgroundColor: const Color(0xFF333333), // Dark grey background
                //     foregroundColor: Colors.white,            // White text color
                //     elevation: 0,                            // Flat design as seen in image
                //     padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                //     shape: const StadiumBorder(),            // Creates the perfect "pill" shape
                //   ).copyWith(
                //     // Adding the hover border logic we discussed
                //     side: WidgetStateProperty.resolveWith<BorderSide>((states) {
                //       if (states.contains(WidgetState.hovered)) {
                //         return const BorderSide(color: Colors.blue, width: 1.5);
                //       }
                //       return BorderSide.none;
                //     }),
                //   ),
                //   child: const Text("Customize"),
                // ),
                // Spacer(),
                // GestureDetector(
                //   child: Icon(IconData(0xe90a, fontFamily: "IcomoonIcons"), size: 20, color: Colors.grey)
                // ),
              ],
            ),
          ),
        ),
      )
          // }),

          );
      children.add(SizedBox(height: 5));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
      // [
      //   // Text(title, style: SoftwareTextStyle().kWtMediumTextStyle),
      // ],
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

  Widget _channelColorSettings(int curChannelIdx) {
    return Consumer2<ChannelColorProvider, DataStatusProvider>(
        builder: (context, prov, dataStatus, _) {
      bool isAudioListen = dataStatus.isMicrophoneData;
      if (isAudioListen && prov.audioColors.isNotEmpty) {
        return _buildChannelColorDropdowns(prov, true, curChannelIdx);
      } else if (!isAudioListen && prov.serialColors.isNotEmpty) {
        return _buildChannelColorDropdowns(prov, false, curChannelIdx);
      } else {
        return const SizedBox.shrink();
      }
    });
  }

  int setupFilterValues(List<int> channelIndices, List<double> filterValues) {
    print("setupFilterValues - START");
    startValue = filterValues[0];
    endValue = filterValues[1];
    double type = filterValues[2];
    print("setupFilterValues - END");
    List<String> filterTypes = [
      "ECG",
      "EEG",
      "EMG",
      "Plant",
      "Neuron",
      "Custom",
    ];

    print(
        "START SETUP FILTER VALUES -- type: $type ||| $filterUsageTypeChannels ||--|| $channelIndices");
    for (int channelIdx in channelIndices) {
      print("channelIdx: $channelIdx");
      if (channelIdx != -1) {
        processingUtil.setBandFilter(channelIdx, startValue, endValue);
        print(
            "filterUsageTypeChannels ${filterTypes[type.floor()]} -- filterUsageTypeChannels: $filterUsageTypeChannels - ${filterTypes[type.floor()]}");
        filterUsageTypeChannels[channelIdx] = filterTypes[type.floor()];
        print(
            "AFTER filterUsageTypeChannels ${filterTypes[type.floor()]} -- filterUsageTypeChannels: $filterUsageTypeChannels - ${filterTypes[type.floor()]}");
        Provider.of<CustomRangeSliderProvider>(context, listen: false)
            .setStartValue(startValue, channelIdx);
        Provider.of<CustomRangeSliderProvider>(context, listen: false)
            .setEndValue(endValue, channelIdx);

        setState(() {});
      }
    }

    print(
        "END SETUP FILTER VALUES -- type: $type ||| $filterUsageTypeChannels ____ DEVICE : ${selectedBoard?.uniqueName}");
    streamScrubBuilderController.add(Random().nextInt(100000));
    if (GraphTemplate.selectedBoard?.uniqueName == "HUMANSB") {
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
        case 5: // CUSTOM
          break;
      }
    }

    bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
    if (isAudioListen) {
      createTabBarConfiguration(
          deviceChannelCount, context.read<ChannelFilterProvider>());
    } else {
      // createTabBarConfiguration(deviceChannelCount, context.read<ChannelFilterProvider>());
    }
    // if () {
    // }
    return 1;
  }

  //https://github.com/BackyardBrains/Spike-Recorder/blob/cdb9686947776ab522027b2078c844b009cb0a33/src/engine/RecordingManager.cpp#L795
  Widget _predefinedFilterSettings(int channelIdx) {
    // startValue: startValue,
    // endValue: endValue,
    // sliderValue: _sliderValue,
    print(
        "_predefinedFilterSettings222 -- filterUsageTypeChannels: $filterUsageTypeChannels -- arrFilterUsageTypeChannel: ${arrFilterUsageTypeChannel[channelIdx]}");
    Widget predefinedFilterWidget = SizedBox();
    List<Widget> listPredefinedFilter =
        buildPredefinedFilter(channelIdx, filterUsageTypeChannels[channelIdx]);

    if (kIsWeb) {
      predefinedFilterWidget = Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: buildPredefinedFilter(
            channelIdx, filterUsageTypeChannels[channelIdx]),
      );
    } else {
      if (Platform.isAndroid || Platform.isIOS) {
        String usageType = arrFilterUsageTypeChannel[channelIdx];
        int pageIdx = predefinedFiltersChannel[channelIdx].indexOf(usageType);

        try {
          if (carouselSliderControllerChannel != null) {
            Future.delayed(Duration(milliseconds: 50), () {
              carouselSliderControllerChannel[channelIdx].jumpToPage(pageIdx);
            });
          } else {
            print("carouselSliderControllerChannel NULLL");
          }
        } catch (err) {
          print("err carousel slider");
          print(err);
        }
        predefinedFilterWidget = CarouselSlider(
          options: CarouselOptions(
            height: 150.0,
            viewportFraction: 0.35,
          ),
          carouselController: carouselSliderControllerChannel[channelIdx],
          items: listPredefinedFilter.map((widget) {
            int i = listPredefinedFilter.indexOf(widget);
            return Builder(
              builder: (BuildContext context) {
                return Container(
                  width: MediaQuery.of(context).size.width,
                  margin: EdgeInsets.symmetric(horizontal: 5.0),
                  child: listPredefinedFilter[i],
                );
              },
            );
          }).toList(),
        );
      } else {
        predefinedFilterWidget = Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: buildPredefinedFilter(
              channelIdx, filterUsageTypeChannels[channelIdx]),
        );
      }
    }
    return Container(
      margin: EdgeInsets.only(top: 20),
      padding: EdgeInsets.fromLTRB(0, 10, 0, 0),
      decoration: BoxDecoration(
        color: Color(0xFF2e2e2e),
        // borderRadius: BorderRadius.circular(16),
        borderRadius: serialUsageType == "Custom"
            ? BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(0),
                topRight: Radius.circular(16), // Keeps the right side flat
                bottomRight: Radius.circular(0),
              )
            : BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                topRight: Radius.circular(16), // Keeps the right side flat
                bottomRight: Radius.circular(16),
              ),
      ),
      child: predefinedFilterWidget,
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

  bool isDarkMode = true;

  bool isDetailConfiguration = false;
  int customizeDetailChannelIdx = 0;

  /// `true` = muted ("Mute Speakers" checked). Default: muted.
  var isSpeakerChannelMuted = List<bool>.filled(10, true);

  List<CustomSliderBarButton> customSliderBarArray = [];

  TabbedViewController? _channelTabController;

  TabbedViewThemeData? channelTabTheme;

  int selectedTabIdx = 0;

  Timer? boardTimer;
  Timer? deviceTimer;
  Timer? _serialStaleWatchdogTimer;

  static const int _serialDataStaleTimeoutSeconds = 7;

  String? accessoryLabel;

  static bool isMfiInitialized = false;

  /// Mic is only detached once when switching to MFi; avoids skipping setup on hot-plug.
  bool _mfiMicListenerDetached = false;

  StreamSubscription<Uint8List>? _rxSub;

  ConnectorType? connectorType;

  DateTime lastEstablishingConnectionTime = DateTime.now();

  String? serialPortId;
  List<String> blacklistSerialPortIds = [];

  // bool isTryingToConnect = false;
  // Int32List arrSampleCountWeb = Int32List(0);
  // Int16List arrSamplesWeb = Int16List(1);

  void startOpeningFileWeb(String filePath, int startIdx, int endIdx) async {
    currentLoadedFilePath = filePath;
    forceSerialDisconnect = false;
    isOpeningFile = false;

    // Int32List arrConfigWeb = Int32List(10);
    // Int32List arrSampleCount = Int32List(widget.channelCount);
    // Int16List arrSamples = Int16List(1);
    // if (currentLoadedFilePath.endsWith(".wav")) {
    //   final wavReader = await Wav.readFile(currentLoadedFilePath);
    //   print("WAV READER2: ${wavReader.samplesPerSecond} ${wavReader.channels.length} ${wavReader.format}");
    //   // GraphTemplate.nwbFileUtil?.processingInit(wavReader.samplesPerSecond, wavReader.channels.length, wavReader., deviceManufacturer, visibleChannelsList, visibleChannelCount)
    //   return;
    // }

    print("======SEEK OPEN FILE - Initiating");
    await GraphTemplate.nwbFileUtil
        ?.startOpeningFileWeb(currentLoadedFilePath, 0, 1, 0, 0);
    // isFileOpenedWeb = await GraphTemplate.nwbFileUtil?.seekElectricalSeries(currentLoadedFilePath, arrSamplesWeb, arrSampleCountWeb, arrConfigWeb, 0, 1, 0, 0);
    print("======SEEK OPEN FILE - FIN");
  }

  void startOpeningFileWebCallbackPlayback(
      config, arrSampleCount, arrSamples, isStartOpeningFileWeb) async {
    // [48000, 1, 885, 0, 1000000, 654337, 0, 0, 0, 0], [196301]
    // Validate config before accessing indices to prevent RangeError
    currentLoadedFilePath = GraphTemplate.nwbFileUtil?.openedNwbFilePath ?? "";
    if (config == null || config is! Int32List || config.length < 10) {
      print(
          "ERROR: Invalid config in startOpeningFileWebCallback: $config (type: ${config.runtimeType}, length: ${config is List ? config.length : 'N/A'})");
      return;
    }
    Map<String, dynamic> map = {};
    map["arrSamples"] = arrSamples;
    map["arrSampleCount"] = arrSampleCount;
    map["loadedConfig"] = config;
    seekElectricalSeriesWebCompleter.complete(map);
  }

  void startOpeningFileWebCallback(
      config, arrSampleCount, arrSamples, isStartOpeningFileWeb) async {
    currentLoadedFilePath = GraphTemplate.nwbFileUtil?.openedNwbFilePath ?? "";
    print(
        "SECTION startOpeningFileWebCallbackPlayback : $config, $arrSampleCount, $isStartOpeningFileWeb ===+++=== $currentLoadedFilePath");
    // Validate config before accessing indices to prevent RangeError
    if (config == null || config is! Int32List || config.length < 10) {
      print(
          "ERROR: Invalid config in startOpeningFileWebCallback: $config (type: ${config.runtimeType}, length: ${config is List ? config.length : 'N/A'})");
      return;
    }
    if (config[0] == 0 || config[1] == 0) {
      print(
          "ERROR: NWB file could not be opened (sample rate or channel count is 0). "
          "Re-open the saved .nwb file from disk.");
      isOpeningFile = false;
      return;
    }

    print(
        "GraphTemplate.nwbFileUtil?.recordedNwbFilePath : ${GraphTemplate.nwbFileUtil?.recordedNwbFilePath}");
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
    _refreshSerialDataArrivalWhileOpeningFile();
    _isSerialWebButtonEnabled = false;

    // STEVE: FIX THIS HARDCODED STUFF
    // config[6] might not be set if device detection fails, default to 0 (audio)
    int isSerialDevice = (config.length > 6) ? config[6] : 0;
    // int isSerialDevice = 0;
    print(
        "IS SERIAL DEVICE : $isSerialDevice | CHANNEL COUNT: ${widget.channelCount}");
    if (isSerialDevice == 1) {
      context.read<DataStatusProvider>().setMicrophoneDataStatus(false);
      Provider.of<ConstantProvider>(context, listen: false)
          .setChannelCount(widget.channelCount);
      Provider.of<SampleRateProvider>(context, listen: false)
          .setSampleRate(sampleRateConfig);
      ProcessingUtil.initializeDevice.value =
          (ProcessingUtil.initializeDevice.value * 10) +
              2 +
              Random().nextInt(10);
      context
          .read<ChannelColorProvider>()
          .setSerialChannelCount(widget.channelCount);
      context
          .read<ChannelFilterProvider>()
          .setSerialChannelCount(widget.channelCount);

      periodicSerialDataSubscription();
      microphoneUtil.micStream.removeListener(micListener);
      microphoneUtil.micStream = ValueNotifier(Uint8List(0));
      // }
    } else {
      context.read<DataStatusProvider>().setMicrophoneDataStatus(true);
      Provider.of<ConstantProvider>(context, listen: false)
          .setChannelCount(widget.channelCount);
      Provider.of<SampleRateProvider>(context, listen: false)
          .setSampleRate(sampleRateConfig);
      ProcessingUtil.initializeDevice.value = 0;
      context
          .read<ChannelColorProvider>()
          .setAudioChannelCount(widget.channelCount);
      periodicTimerSerial?.cancel();
    }
    print("Loaded Max Samples : $loadedMaxSamples -- ${_sampleRate}");

    loadedConfig[7] = MediaQuery.of(context).size.width.toInt();
    // print("INIT WITH CONFIG: $loadedConfig");
    // await processingUtil.initWithConfig(loadedConfig);
    // print("INIT WITH CONFIG FIN: $loadedConfig");

    // Validate arrSampleCount and arrSamples before processing
    if (arrSampleCount == null || arrSamples == null) {
      print(
          "ERROR: arrSampleCount or arrSamples is null. arrSampleCount: $arrSampleCount, arrSamples: $arrSamples");
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
      arrSampleCountList =
          Int32List.fromList(arrSampleCount.map((e) => e as int).toList());
    } else if (arrSampleCount is Int32List) {
      arrSampleCountList = arrSampleCount;
    } else {
      print(
          "ERROR: arrSampleCount is not a valid type: ${arrSampleCount.runtimeType}");
      return;
    }

    if (arrSamples is List) {
      arrSamplesList =
          Int16List.fromList(arrSamples.map((e) => e as int).toList());
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
      double initialSampleCount = arrSampleCountList != null
          ? arrSampleCountList[0].toDouble()
          : arrSampleCount[0].toDouble();
      loadedArrSamples.add(Int16List(initialSampleCount.floor()));
      if (isStartOpeningFileWeb) {
      } else {
        if (arrSamplesList != null &&
            arrSamplesList.length >= combinedIdx + initialSampleCount.floor()) {
          loadedArrSamples[i].setAll(
              0,
              arrSamplesList.sublist(
                  combinedIdx, combinedIdx + initialSampleCount.floor()));
        } else if (arrSamples is List &&
            (arrSamples as List).length >=
                combinedIdx + initialSampleCount.floor()) {
          Int16List tempList = Int16List.fromList((arrSamples as List)
              .sublist(combinedIdx, combinedIdx + initialSampleCount.floor())
              .map((e) => e as int)
              .toList());
          loadedArrSamples[i].setAll(0, tempList);
        }
      }
      // loadedArrChannelCount.fillRange(0, totalChannelCount, initialSampleCount.floor());
      loadedArrChannelCount[i] = initialSampleCount.floor();
      combinedIdx += initialSampleCount.floor();
    }
    print(
        "Loaded Arr Samples Status: ${loadedArrSamples.length} || arrSampleCount: ${arrSampleCount}");

    // Reset processing buffer when scrubbing (not initial file opening)
    print(
        "IS START OPENING FILE WEB: $isStartOpeningFileWeb | kIsWeb: ${kIsWeb} | widget.channelCount: ${widget.channelCount} | config: $config");
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
        unawaited(_pauseLiveMonitorForFilePlayback());
        Provider.of<GraphResumePlayProvider>(context, listen: false)
            .setGraphResumePlay(false);
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
        scrubNotifier.value = [
          (AdaptiveAreaState.horizontalDragX),
          scrubMaxWidth
        ];
        streamScrubBuilderController.add(Random().nextInt(100000));
      }

      setState(() {});
    });
    context.read<GraphDataProvider>().broadcastDisplayTime(10000.0);

    return;
  }

  void startOpeningFile(String filePath) async {
    currentLoadedFilePath = filePath;
    forceSerialDisconnect = false;
    print("INIT NWB FILE");
    isOpeningFile = true;
    _refreshSerialDataArrivalWhileOpeningFile();
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
    print("CURRENT LOADED FILEzzzqqqqq PATH: $currentLoadedFilePath");
    if (currentLoadedFilePath.endsWith(".wav")) {
      String? recordedFilePath = "";
      Wav wavReader;
      try {
        wavReader = await readWavFromPath(currentLoadedFilePath);
      } on FormatException catch (e, st) {
        debugPrint('Failed to read WAV: $e\n$st');
        if (context.mounted) {
          PanaraInfoDialog.show(
            context,
            textColor: Colors.red,
            title: "Error",
            message:
                "Could not open this WAV file. It may be corrupted or use an unsupported format.",
            buttonText: "Okay",
            onTapDismiss: () => Navigator.pop(context),
            panaraDialogType: PanaraDialogType.error,
            barrierDismissible: false,
          );
        }
        isOpeningFile = false;
        return;
      }
      final wavChannelCount = wavReader.channels.length;
      final wavSampleRate = wavReader.samplesPerSecond;
      if (wavChannelCount > 1) {
        recordedFilePath = await GraphTemplate.nwbFileUtil?.processingInit(
            wavSampleRate,
            wavChannelCount,
            "SpikeRecorder Device|||",
            "SpikeRecorder Systems@@@LegacyFormat",
            visibleSignalsList,
            visibleChannelCount);

        print(
            "WAV READER2: ${wavReader.samplesPerSecond} ${wavReader.channels.length} ${wavReader.format}");
      } else {
        recordedFilePath = await GraphTemplate.nwbFileUtil?.processingInit(
            wavSampleRate,
            wavChannelCount,
            "Audio|||",
            "SpikeRecorder Systems",
            visibleSignalsList,
            visibleChannelCount);
      }

      final channels = wavReader.channels;
      final samplesCount = Int32List(channels.length);
      var totalSamples = 0;
      for (var c = 0; c < channels.length; c++) {
        samplesCount[c] = channels[c].length;
        totalSamples += channels[c].length;
      }
      final flattenedList = Int16List(totalSamples);
      var offset = 0;
      for (var c = 0; c < channels.length; c++) {
        final ch = channels[c];
        for (var i = 0; i < ch.length; i++) {
          // Inverse of package:wav int16 decode: intToSample(fold(uint16), 16) uses divisor 32767.5.
          final f = ch[i].clamp(-1.0, 1.0);
          final u = ((f + 1.0) * 32767.5).round().clamp(0, 65535);
          flattenedList[offset + i] = u - 32768;
        }
        offset += ch.length;
      }
      // STEVE: native nwbfile_add_electrical_series reads samplesCount[0..channelCount-1] and
      // copies channelCount slices from inSamples — channelCount must match WAV channels and
      // processingInit. Do not finish with an empty Int16List; native still std::copies by samplesCount.
      if (!kIsWeb) {
        GraphTemplate.nwbFileUtil?.addElectricalSeries(
            flattenedList, samplesCount, 0, wavChannelCount, 1);
      }
      currentLoadedFilePath = recordedFilePath ?? "";

      // final wavReader = await Wav.readFile(currentLoadedFilePath);
      // print("WAV READER: ${wavReader.samplesPerSecond} ${wavReader.channels.length} ");
      // wavReader.channels
    } else {}
    print("======SEEK OPEN FILE - Initiating");
    bool? isFileOpened = await GraphTemplate.nwbFileUtil?.seekElectricalSeries(
        currentLoadedFilePath,
        arrSamples,
        arrSampleCount,
        arrConfig,
        0,
        1,
        0,
        0);
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
    print("ARR CONFIG: $arrConfig | sampleRateConfig: $sampleRateConfig");

    loadedConfig.setAll(0, arrConfig);
    loadedMaxSamples = arrConfig[5].toDouble();
    _sampleRate = sampleRateConfig;
    int isSerialDevice = arrConfig[6];
    print(
        "IS SERIAL DEVICE : $isSerialDevice | CHANNEL COUNT: ${widget.channelCount} ___ $_sampleRate ___ ${GraphTemplate.selectedBoard?.uniqueName}");
    if (isSerialDevice == 1) {
      // GraphTemplate.selectedBoard = Board(maxSampleRate: sampleRateConfig.toString(), maxNumberOfChannels: widget.channelCount.toString());
      // processingUtil.initializeSerial(GraphTemplate.selectedBoard!, MediaQuery.of(context).size.width);
      // if (context.mounted) {

      if (GraphTemplate.selectedBoard?.uniqueName == "HHIBOX") {
        sampleCountToDisplay = (_sampleRate / 5000 * 8 * 2).floor();
      } else if (GraphTemplate.selectedBoard?.uniqueName == "NRNSBPRO") {
        sampleCountToDisplay =
            (_sampleRate / 5000 * 8 * defaultDeviceChannelCount).floor();
      } else if (_sampleRate >= 10000 && defaultDeviceChannelCount < 2) {
        sampleCountToDisplay = (_sampleRate / 5000 * 8 * 2).floor();
      } else if (_sampleRate >= 10000 && defaultDeviceChannelCount > 1) {
        sampleCountToDisplay = (_sampleRate / 5000 * 8 * 2).floor();
      } else {
        sampleCountToDisplay = (_sampleRate / 5000 * 8 * 2).floor();
      }

      context.read<DataStatusProvider>().setMicrophoneDataStatus(false);
      Provider.of<ConstantProvider>(context, listen: false)
          .setChannelCount(widget.channelCount);
      Provider.of<SampleRateProvider>(context, listen: false)
          .setSampleRate(sampleRateConfig);
      ProcessingUtil.initializeDevice.value =
          (ProcessingUtil.initializeDevice.value * 10) +
              2 +
              Random().nextInt(10);
      context
          .read<ChannelColorProvider>()
          .setSerialChannelCount(widget.channelCount);
      context
          .read<ChannelFilterProvider>()
          .setSerialChannelCount(widget.channelCount);

      periodicSerialDataSubscription();
      // }
    } else {
      context.read<DataStatusProvider>().setMicrophoneDataStatus(true);
      Provider.of<ConstantProvider>(context, listen: false)
          .setChannelCount(widget.channelCount);
      Provider.of<SampleRateProvider>(context, listen: false)
          .setSampleRate(sampleRateConfig);
      ProcessingUtil.initializeDevice.value = 0;
      context
          .read<ChannelColorProvider>()
          .setAudioChannelCount(widget.channelCount);
      periodicTimerSerial?.cancel();
    }
    print("Loaded Max Samples : $loadedMaxSamples -- ${_sampleRate}");

    loadedConfig[7] = MediaQuery.of(context).size.width.toInt();
    await processingUtil.initWithConfig(loadedConfig);
    GraphTemplate.isPlayerPaused = true;
    if (isSerialDevice == 0) {
      microphoneUtil.micStream.value = Uint8List(0);
    }
    Provider.of<GraphResumePlayProvider>(context, listen: false)
        .setGraphResumePlay(false);
    GraphTemplate.isLoadingFile = 1;
    // return;

    AdaptiveAreaState.maxTime = loadedMaxSamples / _sampleRate;
    print(
        "AdaptiveAreaState.maxTime: $AdaptiveAreaState.maxTime | loadedMaxSamples: $loadedMaxSamples | _sampleRate: $_sampleRate");
    // AdaptiveAreaState.strMaxTime = loadedMaxSamples / _sampleRate;
    double scrubMaxWidth = MediaQuery.of(context).size.width - 100 - 20;
    // AdaptiveAreaState.horizontalDragX = scrubMaxWidth * 0.3;
    // scrubNotifier.value = [ (scrubMaxWidth * 0.3), scrubMaxWidth];
    double multiplier = _sampleRate / loadedMaxSamples;
    AdaptiveAreaState.horizontalDragX = multiplier * scrubMaxWidth;
    if (multiplier >= 1) {
      AdaptiveAreaState.horizontalDragX = scrubMaxWidth * 0.3;
    }
    scrubNotifier.value = [(AdaptiveAreaState.horizontalDragX), scrubMaxWidth];
    streamScrubBuilderController.add(Random().nextInt(100000));

    setState(() {});
    return;

    print("sampleRateConfig: $sampleRateConfig $arrConfig");
    double arrSamplesLength =
        ProcessingUtil.MAX_DISPLAY_SECONDS * sampleRateConfig;
    // double arrSamplesLength = loadedMaxSamples;
    // double arrSamplesLength = maxSamples.toDouble();

    // // Calculate total data points needed for multi-channel reading
    // int samplesPerChannel = arrSamplesLength.floor();
    // int numChannels = 2; // Reading channels 0-1
    // int totalDataPoints = samplesPerChannel * numChannels;

    arrSamples = Int16List(arrSamplesLength.floor() * widget.channelCount);

    // await GraphTemplate.nwbFileUtil?.seekElectricalSeries(arrSamples, arrSampleCount, arrConfig, 0, arrSamplesLength.floor(), 0, 1);
    double startSeekSample = 0;
    double endSeekSample =
        arrSamplesLength; // (arrSamplesLength - startSeekSample).floor()
    startSeekSampleIdx = startSeekSample;
    endSeekSampleIdx = endSeekSample;
    if (endSeekSampleIdx > loadedMaxSamples) {
      endSeekSampleIdx = loadedMaxSamples;
      endSeekSample = loadedMaxSamples.toDouble();
    }
    // endSeekSampleIdx = loadedMaxSamples;
    // endSeekSample = loadedMaxSamples.toDouble();

    await Future.delayed(Duration(milliseconds: 100));

    print(
        "FINISH WAITINGGGGGG END SEEK SAMPLE IDX: $endSeekSampleIdx $loadedMaxSamples");
    await GraphTemplate.nwbFileUtil?.seekElectricalSeries(
        currentLoadedFilePath,
        arrSamples,
        arrSampleCount,
        loadedConfig,
        (startSeekSample).floor(),
        endSeekSample.floor(),
        0,
        widget.channelCount - 1);
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
      loadedArrSamples[i].setAll(
          0,
          arrSamples.sublist(
              combinedIdx, combinedIdx + initialSampleCount.floor()));
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
    print(
        "setGraphResumePlay PLAYBACK INIT : $combinedIdx | $totalChannelCount");
    Provider.of<GraphResumePlayProvider>(context, listen: false)
        .setGraphResumePlay(false);
    GraphTemplate.isLoadingFile = 1;

    // serialNativeDataSubscription(Uint8List(0), false);
    setState(() {});
  }

  void serialNativeDataSubscription(Uint8List event, bool isAudioListen) async {
    final provider = Provider.of<GraphDataProvider>(context, listen: false);
    int drawSurfaceWidth = MediaQuery.of(context).size.width.toInt();

    if (GraphTemplate.isLoadingFile == 2 || GraphTemplate.isLoadingFile == 4) {
      // print("Graph Template isLoadingFile 2/4: ${GraphTemplate.isLoadingFile}");
      await _paintSerialFileGraph(provider, drawSurfaceWidth);
      setState(() {});
    } else if (GraphTemplate.isLoadingFile == 1) {
      // print("Graph Template isLoadingFile 1: ${GraphTemplate.isLoadingFile}");
      GraphTemplate.isLoadingFile = 2;
      // SERIAL FILE CHANGES
      // List<Int16List> tempData = processingUtil.processMicrophoneData(loadedArrSamples[0].buffer.asUint8List());
      int channelIdx = 0;
      Int32List samplesCount = Int32List(loadedArrSamples.length);
      Int16List flattenedList =
          Int16List.fromList(loadedArrSamples.expand((list) {
        samplesCount[channelIdx] = loadedArrSamples[channelIdx].length;
        channelIdx++;
        return list;
      }).toList());
      // print("SAMPLES COUNT: $samplesCount");
      // print("WIDGET CHANNEL COUNT: $widget.channelCount");
      // processingUtil.processingNwbFileInjectData(flattenedList, samplesCount, 0, widget.channelCount);
      processingUtil.processingSerialDataResult(
          flattenedList, samplesCount, widget.channelCount);
      if (kIsWeb) {
        totalSampleCount += loadedArrSamples[0].length;
        _scheduleSerialGraphPaint(provider, drawSurfaceWidth);
      }
    } else if (GraphTemplate.isLoadingFile == 3) {
      // print("Graph Template isLoadingFile 3: ${GraphTemplate.isLoadingFile}");
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
      if (!isAudioListen && event.isNotEmpty && _shouldRunLiveMonitor()) {
        _registerWebLivePlaybackListener();
        unawaited(_ensureLiveMonitorPlayer());
      }
      if (!GraphTemplate.isPlayerPaused) {
        if (event.isNotEmpty) {
          _enqueueSerialIngest(event, provider, drawSurfaceWidth);
        }
      } else {
        if (isThresholdingButton) {
          if (arr.isEmpty || arr[0] <= 0) {
            arr = [
              kIsWeb
                  ? processingUtil.thresholdingArraylength
                  : (displayTimeMs * 0.001 * _sampleRate)
                      .floor()
                      .clamp(1, 1 << 30)
            ];
          }
          if (arr.isEmpty || arr[0] <= 0) {
            arr = [
              (displayTimeMs * 0.001 * _sampleRate).floor().clamp(1, 1 << 30)
            ];
          }
          double displayTimeDivision = (displayTimeMs / 10000);
          double gap = (arr[0] * (1 - displayTimeDivision));
          int maxSamples =
              (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
          int toSample = maxSamples - (gap / 2).floor();
          int fromSample = toSample - arr[0] + (gap).floor();
          DraggableGraph.startPositionIdx = fromSample;
          DraggableGraph.endPositionIdx = toSample;

          await processingUtil.processDisplaySerialData(displayTimeMs.toInt(),
              deviceType, drawSurfaceWidth, provider, fromSample, toSample);
        } else {
          int maxSamples =
              (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
          int toSample = (maxSamples + bufferPaddingLeft).toInt();
          toSample = min(maxSamples, toSample);
          int fromSample =
              (toSample - displayTimeMs * 0.001 * _sampleRate).toInt();
          DraggableGraph.startPositionIdx = fromSample;
          DraggableGraph.endPositionIdx = toSample;
          // processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, fromSample, toSample );
          await processingUtil.processDisplaySerialData(displayTimeMs.toInt(),
              deviceType, drawSurfaceWidth, provider, fromSample, toSample);
        }
        // provider.inputListener(Uint8List(0));
      }
    }
    provider.inputListener(Uint8List(0));
  }

  void periodicSerialDataSubscription() {
    periodicTimerSerial?.cancel();
    // Refreshes loaded-file / paused graph only (empty payload). Live UART RX does
    // not use this timer — see [serialSubscriptionListener] + [_drainSerialIngestQueue].
    // timeMs ≈ 100 ms at dummySamplingRate 10 kHz; not the live playback delay source.

    periodicTimerSerial =
        Timer.periodic(Duration(milliseconds: timeMs), (timer) {
      bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
      // List<String> listOfPort = Provider.of<PortScanProvider>(context, listen: false).availablePorts;
      serialNativeDataSubscription(Uint8List(0), isAudioListen);
      // print("periodicSerialDataSubscription");
    });
  }

  List<Widget> generateThresholdSlider(isHorizontal) {
    if (!kIsWeb && isHorizontal && Platform.isAndroid) {
      return [];
    }
    return [
      Center(
        child: DropdownButtonHideUnderline(
          child: DropdownButton2(
            customButton: generateSpikerBoxDecorate(
                eventThresholdTriggeredType == "Signal"
                    ? Icon(Icons.stacked_line_chart_outlined)
                    : Center(
                        child: Text(
                        eventThresholdTriggeredType.substring(0, 2),
                      ))),
            items: listMenuLabels
                .map((item) => DropdownMenuItem<String>(
                      value: item,
                      child: Text(item),
                    ))
                .toList(),
            onChanged: (value) {
              print("TRIGGER TYPE : $value");
              eventThresholdTriggeredType = value!;
              int triggerType =
                  listMenuOptions.indexOf(eventThresholdTriggeredType);
              processingUtil.setThresholdTriggerType(triggerType);
              context
                      .read<ThresholdStatusProvider>()
                      .selectedThresholdTriggerType =
                  listMenuOptions.indexOf(eventThresholdTriggeredType);
              setState(() {});
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
          height: 30,
          child: FlutterSlider(
            onDragging: (handlerIndex, lowerValue, upperValue) {
              print("handlerIndex:  $handlerIndex $lowerValue - $upperValue");
              if (handlerIndex == 1) {
                thresholdSliderValue = lowerValue.floor();
                processingUtil.setAveragedSampleCount(lowerValue.floor());
                setState(() {});
              }
            },
            onDragCompleted: (handlerIndex, lowerValue, upperValue) {},
            tooltip: FlutterSliderTooltip(
              disabled: true,
            ),
            min: 1,
            max: 50,

            handlerHeight: 50,
            handlerWidth: 50,
            handler: FlutterSliderHandler(
              decoration: BoxDecoration(),
              child: Container(
                width: 80,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  // shape: BoxShape.circle,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      spreadRadius: 0.05,
                      blurRadius: 5,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
            // handler: FlutterSliderHandler(
            //   child: Material(
            //     type: MaterialType.canvas,
            //     color: Colors.grey.shade500,
            //     elevation: 3,
            //     child: Container(
            //         padding: EdgeInsets.all(5),
            //         // child: Icon(Icons.adjust, size: 25,)
            //       ),
            //   ),
            //   decoration: BoxDecoration(
            //     borderRadius: BorderRadius.circular(0),
            //     color: Colors.grey,
            //     border: Border.all(width: 3, color: Colors.white),
            //   )
            // ),
            trackBar: FlutterSliderTrackBar(
              activeTrackBarHeight: 40,
              inactiveTrackBarHeight: 40,
              activeTrackBar: BoxDecoration(
                // borderRadius: BorderRadius.circular(0),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  topRight: Radius.circular(0), // Keeps the right side flat
                  bottomRight: Radius.circular(0),
                ),
                color: Color(0xFFFF7F5C), // The coral color from your image
              ),
              inactiveTrackBar: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: Color(0xFF1E1E1E), // Dark background color
              ),
            ),
            // trackBar: FlutterSliderTrackBar(
            //   inactiveTrackBarHeight: 70,
            //   activeTrackBarHeight: 70,
            //   inactiveTrackBar: BoxDecoration(
            //     borderRadius: BorderRadius.circular(0),
            //     color: Colors.grey,
            //     border: Border.all(width: 3, color: Colors.black45),
            //   ),
            //   activeTrackBar: BoxDecoration(
            //     borderRadius: BorderRadius.circular(0),
            //     color: Colors.grey.withOpacity(0.5)
            //   ),
            // ),
            values: [thresholdSliderValue.floorToDouble()],
          )),
      Container(
        margin: EdgeInsets.only(top: 15, left: 10),
        height: 30,
        child: Text(thresholdSliderValue.toString(),
            style: TextStyle(color: Colors.white)),
      ),
    ];
  }

  void initMessageIdentifier() {
    _messageIdentifier = MessageIdentifier(onDeviceData: (Uint8List dt) {
      if (forceSerialDisconnect) return;
      List<int> devData = dt;
      // print("devData: $devData");

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
      // print("portListOnConnect MESSAGE IDENTIFIER ONDEVICE MESSAGE");
      if (forceSerialDisconnect) return;
      String rawMessage = String.fromCharCodes(msg);
      // if (rawMessage.indexOf("EVNT") > -1) {
      //   String responseMessage = MessageValueSet.fromUint8ListCommand(message: msg).value;
      //   responseMessage = responseMessage.replaceAll(";", "");
      //   int eventIndex =
      //   return;
      // }
      String responseMessage =
          MessageValueSet.fromUint8ListCommand(message: msg).value;
      print("responseMessage :  $responseMessage - raw: $rawMessage");
      String? devices = checkConnectedDevices(responseMessage);

      if (devices == null) {
        return;
      }
      // if (_deviceName.value != null) {
      //   deviceType = listOfDevices.indexOf(_deviceName.value!);
      //   print("deviceType");
      //   print(deviceType);
      // }

      SetUpFunctionality().setTheDeviceSetting(devices).then((value) {
        print("VALUE : $value");
        if (value != null) {
          String tempDevices = value.uniqueName ?? "";
          // Ignore duplicate hwType replies only after this device is already selected.
          if (foundDevices == tempDevices && isDeviceSelected) {
            return;
          }
          foundDevices = tempDevices;
          print("foundDevices");
          print(foundDevices);
          isDeviceSelected = true;
          // HARDCODE
          // if (foundDevices == "MUSCLESS") {
          //   foundDevices = "HEARTSS";
          // }
          if (isMfiDeviceConnect) {
            context.read<DataStatusProvider>().setMicrophoneDataStatus(false);
          } else {
            context
                .read<DataStatusProvider>()
                .setMicrophoneDataStatus(_availablePorts.isEmpty);
          }
          Provider.of<ConstantProvider>(context, listen: false)
              .setBaudRate(foundDevices == "HHIBOX" ? 500000 : 222222);
          Provider.of<ConstantProvider>(context, listen: false)
              .setChannelCount(int.parse(value.maxNumberOfChannels.toString()));
          widget.channelCount = int.parse(value.maxNumberOfChannels.toString());
          // print("widget.channelCount: $widget.channelCount");

          Provider.of<ConstantProvider>(context, listen: false)
              .setBitData(int.parse(value.sampleResolution.toString()));
          Provider.of<SampleRateProvider>(context, listen: false)
              .setSampleRate(int.parse(value.maxSampleRate.toString()));

          connectedDevices.add(foundDevices);
          SerialPortDataModel serialData = SerialPortDataModel(
              portCom: portName, deviceDetect: foundDevices);
          context.read<SerialDataProvider>().setPortOfDevices(serialData);
          _emitConnectedDeviceBoardList();
          // if (isDeviceConnect) {
          bool isAudioListen =
              context.read<DataStatusProvider>().isMicrophoneData;
          print("isDeviceConnect: ");
          print("$isDeviceConnect -- isAudioListen : $isAudioListen");
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
                  // GraphTemplate.selectedBoard?.uniqueName = "NRNSBPRO";

                  _deviceName.value =
                      GraphTemplate.selectedBoard?.userFriendlyFullName;
                  // HARDCODE
                  deviceType = listOfDevices.indexOf("$foundDevices;");
                  print(
                      "DEVICE devices :   $devices = VALUE: ${_deviceName.value} ==== device Type: $deviceType");
                  // (processingUtil as ProcessingUtilImpl).dispose();
                  // processingUtil = createProcessingUtil();
                  _sampleRate = int.parse(board.maxSampleRate!);
                  print(
                      "sampleCountToDisplay == $sampleCountToDisplay !!!!@@@@");
                  print(
                      "SAMPLE RAtE: $_sampleRate -----${GraphTemplate.selectedBoard} ${board.uniqueName} --- $foundDevices ::: ${board.uniqueName == foundDevices} $deviceType");
                  double drawSurfaceWidth = MediaQuery.of(context).size.width;
                  processingUtil.initializeSerial(board, drawSurfaceWidth);
                  if (!isAudioListen) {
                    _registerWebLivePlaybackListener();
                    unawaited(_ensureLiveMonitorPlayer(
                      channelCount: int.parse(board.maxNumberOfChannels!),
                    ));
                  }
                  ProcessingUtil.initializeDevice.value = 1;
                  processingUtil.defaultChannelCountNoExpansionBoard =
                      int.parse(board.maxNumberOfChannels!);
                  processingUtil.defaultSampleRateNoExpansionBoard =
                      int.parse(board.maxSampleRate!);
                  if (!kIsWeb) {
                    print("microphoneUtil.micStatus?.cancel()");
                    microphoneUtil.micStatus?.cancel();
                  }

                  deviceChannelCount = int.parse(board.maxNumberOfChannels!);
                  defaultDeviceChannelCount = deviceChannelCount;

                  if (GraphTemplate.selectedBoard?.uniqueName == "HHIBOX") {
                    if (kIsWeb) {
                      sampleCountToDisplay = (_sampleRate / 5000 * 8).floor();
                      // sampleCountToDisplay = (_sampleRate / 5000 * 4).floor();
                    } else {
                      sampleCountToDisplay =
                          (_sampleRate / 5000 * 8 * 2).floor();
                    }
                  } else if (GraphTemplate.selectedBoard?.uniqueName ==
                      "NRNSBPRO") {
                    sampleCountToDisplay =
                        (_sampleRate / 5000 * 8 * defaultDeviceChannelCount)
                            .floor();
                  } else if (_sampleRate >= 10000 &&
                      defaultDeviceChannelCount < 2) {
                    sampleCountToDisplay = (_sampleRate / 5000 * 8 * 2).floor();
                  } else if (_sampleRate >= 10000 &&
                      defaultDeviceChannelCount > 1) {
                    sampleCountToDisplay =
                        (_sampleRate / 5000 * 8 * defaultDeviceChannelCount)
                            .floor();
                  } else {
                    sampleCountToDisplay = (_sampleRate / 5000 * 8 * 2).floor();
                  }

                  context.read<ChannelColorProvider>().setSerialChannelCount(
                      int.parse(board.maxNumberOfChannels!));
                  context.read<ChannelFilterProvider>().setSerialChannelCount(
                      int.parse(board.maxNumberOfChannels!));
                  print(
                      "SERIAL BOARD CHANNEL COUNT : ${widget.channelCount} -- sampleCountToDisplay: $sampleCountToDisplay");

                  filterUsageTypeChannels.clear();
                  for (int idxChannel = 0;
                      idxChannel < widget.channelCount;
                      idxChannel++) {
                    filterUsageTypeChannels.add("EMG");
                  }

                  // createDisplaySerialDataIsolate();
                  // createProcessSerialDataIsolate();
                  Future.delayed(Duration(seconds: 2), () {
                    // var info = processingUtil.getInformation();
                    // print("info : $info");
                    if (GraphTemplate.selectedBoard?.uniqueName == "HUMANSB") {
                      print(
                          "infozzz : ${GraphTemplate.selectedBoard?.uniqueName}");
                      predefinedFiltersChannel.clear();
                      for (int i = 0; i < deviceChannelCount; i++) {
                        predefinedFiltersChannel
                            .add(["EMG", "ECG", "EEG", "Custom"]);
                      }
                      arrFilterUsageTypeChannel.clear();
                      for (int i = 0; i < deviceChannelCount; i++) {
                        // arrFilterUsageTypeChannel.add("EMG");
                        arrFilterUsageTypeChannel.add("");
                      }
                      // serialUsageType = "EMG";
                      serialUsageType = "";
                    } else if (GraphTemplate.selectedBoard?.uniqueName ==
                        "NRNSBPRO") {
                      predefinedFiltersChannel.clear();
                      for (int i = 0; i < deviceChannelCount; i++) {
                        predefinedFiltersChannel.add(["Neuron", "Custom"]);
                      }
                      arrFilterUsageTypeChannel.clear();
                      for (int i = 0; i < deviceChannelCount; i++) {
                        // arrFilterUsageTypeChannel.add("Neuron");
                        arrFilterUsageTypeChannel.add("");
                      }
                      // serialUsageType = "Neuron";
                      serialUsageType = "";
                    } else if (GraphTemplate.selectedBoard?.uniqueName ==
                        "PLANTSS") {
                      predefinedFiltersChannel.clear();
                      for (int i = 0; i < deviceChannelCount; i++) {
                        predefinedFiltersChannel.add(["Plant", "Custom"]);
                      }
                      arrFilterUsageTypeChannel.clear();
                      for (int i = 0; i < deviceChannelCount; i++) {
                        // arrFilterUsageTypeChannel.add("Plant");
                        arrFilterUsageTypeChannel.add("");
                      }

                      // serialUsageType = "Plant";
                      serialUsageType = "";
                    }

                    customSliderBarArray.clear();
                    for (int idxChannel = 0;
                        idxChannel < deviceChannelCount;
                        idxChannel++) {
                      customSliderBarArray.add(
                        CustomSliderBarButton(
                          channelIdx: idxChannel,
                          channelCount: widget.channelCount,
                          processingUtil: processingUtil,
                          isMicrophoneEnable: (bool isMicrophoneEnable) {
                            context
                                .read<DataStatusProvider>()
                                .setMicrophoneDataStatus(isMicrophoneEnable);
                          },
                          onHighPassFilterSetup: (FilterSetup filterSetup) {
                            // Keep this for backward compatibility if needed
                          },
                          onLowPassFilterSetup: (FilterSetup filterSetup) {
                            // Keep this for backward compatibility if needed
                          },
                          onSampleChange: (bool isSampleDataOn) {
                            context
                                .read<DataStatusProvider>()
                                .setSampleDataStatus(isSampleDataOn);
                          },
                          startValue: startValue,
                          endValue: endValue,
                          sliderValue: _sliderValue,
                        ),
                      );
                    }
                    createTabBarConfiguration(deviceChannelCount,
                        context.read<ChannelFilterProvider>());
                    setState(() {});
                  });
                }
              }

              // Print the stream (optional)
            });
          }
        }
      });
      Debugging.printing(
          "Message received from Spikerbox: \n\tbytes : $msg\n\tstring: ${String.fromCharCodes(msg)}");
      //     Message received from Spikerbox:
      // bytes : [72, 87, 84, 58, 72, 85, 77, 65, 78, 83, 66, 59]
      // string: HWT:HUMANSB;
    });
  }

  int counterThreshold = 0;

  DateTime? lastDateTimeSerialDataArrival = DateTime.now();
  void _startPlaybackTimer() {
    print("START PLAYBACK TIMER");
    _isStreamEnded = false; // Reset flag when starting playback
    timerPlaybackLoadedFile?.cancel();
    timerPlaybackLoadedStartIndex = 0;
    timerPlaybackLoadedEndIndex = 0;
    double playbackFactor = _sampleRate / 1000;
    bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;

    Future.delayed(Duration(milliseconds: 100), () {
      int prevTime = DateTime.now().millisecondsSinceEpoch;
      bool isPlayback = true;
      timerPlaybackLoadedFile =
          Timer.periodic(Duration(milliseconds: 50), (timer) async {
        GraphTemplate.isLoadingFile = 4;
        int timeDiff = DateTime.now().millisecondsSinceEpoch - prevTime;
        sampleDivider = (timeDiff * playbackFactor);
        prevTime = DateTime.now().millisecondsSinceEpoch;

        try {
          timerPlaybackLoadedEndIndex =
              timerPlaybackLoadedStartIndex + sampleDivider;
          if (startPlaybackSeekSampleIdx + timerPlaybackLoadedEndIndex >
              loadedMaxSamples) {
            timerPlaybackLoadedEndIndex = loadedArrSamples[0].length - 1;
          }

          // create sublist array based on the start and end timer index
          // check if the sublist array is not empty
          // insert data into c++

          final playbackStartIdx = timerPlaybackLoadedStartIndex.floor();
          final playbackEndIdx = timerPlaybackLoadedEndIndex.floor();
          if (playbackEndIdx <= playbackStartIdx) {
            return;
          }

          List<Int16List> sublistArray = [];
          for (int i = 0; i < widget.channelCount; i++) {
            Int16List sublistSamples =
                loadedArrSamples[i].sublist(playbackStartIdx, playbackEndIdx);
            sublistArray.add(sublistSamples);
            if (!_isStreamEnded && loadedFileStreams[i] != null) {
              try {
                if (kIsWeb) {
                  soloud!.addAudioDataStream(
                    loadedFileStreams[i]!,
                    _loadedFilePcmBytes(sublistSamples),
                  );
                }
              } catch (e) {
                // Stream may have been ended, stop trying to add data
                print("Error adding audio data to stream (may be ended): $e");
                _isStreamEnded = true;
                timerPlaybackLoadedFile?.cancel();
                return;
              }
            }
          }
          // print(
          //     "loadedArrSamples: Channel: ${widget.channelCount} --- LENGTH: ${timerPlaybackLoadedEndIndex - timerPlaybackLoadedStartIndex}");
          timerPlaybackLoadedStartIndex =
              (timerPlaybackLoadedStartIndex + sampleDivider);

          if (startPlaybackSeekSampleIdx + timerPlaybackLoadedStartIndex >
              loadedMaxSamples) {
            timerPlaybackLoadedStartIndex = loadedMaxSamples - 1;
            double startSeekSampleLocal = endSeekSampleIdx.toDouble();
            double endSeekSampleLocal = loadedMaxSamples.toDouble();
            startPlaybackSeekSampleIdx = startSeekSampleLocal;
            endSeekSampleIdx = endSeekSampleLocal;

            print("ARR SAMPLES ZERO STOPPING");
            Provider.of<GraphResumePlayProvider>(context, listen: false)
                .setGraphResumePlay(false);
            Int32List arrSampleCount = Int32List(widget.channelCount);
            Int16List arrSamples = Int16List((endSeekSampleIdx.floor() -
                    startPlaybackSeekSampleIdx.floor()) *
                widget.channelCount);
            if (startSeekSampleLocal != endSeekSampleLocal) {
              print(
                  "startSeekSampleLocal != endSeekSampleLocal ::: $startSeekSampleLocal != $endSeekSampleLocal");

              await GraphTemplate.nwbFileUtil?.seekElectricalSeries(
                  currentLoadedFilePath,
                  arrSamples,
                  arrSampleCount,
                  loadedConfig,
                  (startSeekSampleLocal).floor(),
                  endSeekSampleLocal.floor(),
                  0,
                  widget.channelCount - 1);
            }
            GraphTemplate.isLoadingFile = 2;
            GraphTemplate.isPlayerPaused = true;

            timerPlaybackLoadedStartIndex = 0;
            timerPlaybackLoadedEndIndex = 0;
            startPlaybackSeekSampleIdx = 0;
            endSeekSampleIdx = 0;
            _isStreamEnded = true;
            print("ARR SAMPLES ZERO STOPPING 2 - CANCEL TIMER");

            double playbackPercentage =
                (startPlaybackSeekSampleIdx + timerPlaybackLoadedStartIndex) /
                    (loadedMaxSamples);
            AdaptiveAreaState.horizontalDragX =
                playbackPercentage * AdaptiveAreaState.horizontalDragXFix;
            print(
                "AdaptiveAreaState.horizontalDragX :  ${AdaptiveAreaState.horizontalDragX}");

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
            List<Int16List> tempData = processingUtil
                .processMicrophoneData(sublistArray[0].buffer.asUint8List());
            microphoneUtil.micStream.value = Uint8List(0);

            if (!kIsWeb && isThresholdingButton) {
              int selectedThresholdChannelIdx = context
                  .read<ThresholdStatusProvider>()
                  .selectedThresholdChannel;
              bool isAverageSamples = true;
              arr = processingUtil.processThresholdData(
                  tempData,
                  tempData.length,
                  MediaQuery.of(context).size.width.floor(),
                  selectedThresholdChannelIdx,
                  isAverageSamples);
            }
          } else {
            GraphTemplate.isLoadingFile = 4;
            if (kIsWeb) {
              if (context.mounted) {
                final provider =
                    Provider.of<GraphDataProvider>(context, listen: false);
                final drawSurfaceWidth =
                    MediaQuery.of(context).size.width.toInt();
                _enqueueSerialIngest(
                  Uint8List(0),
                  provider,
                  drawSurfaceWidth,
                  decodedChannels: sublistArray,
                );
              }
            } else {
              int channelIdx = 0;
              Int32List samplesCount = Int32List(sublistArray.length);
              Int16List flattenedList =
                  Int16List.fromList(sublistArray.expand((list) {
                samplesCount[channelIdx] = sublistArray[channelIdx].length;
                channelIdx++;
                return list;
              }).toList());
              processingUtil.processingSerialDataResult(
                  flattenedList, samplesCount, widget.channelCount);
            }
            List<Int16List> tempData = sublistArray;
            if (!kIsWeb && isThresholdingButton) {
              print("Process Threshold Data");
              int selectedThresholdChannelIdx = context
                  .read<ThresholdStatusProvider>()
                  .selectedThresholdChannel;
              bool isAverageSamples = true;
              /*
              arr = processingUtil.processThresholdData(
                  tempData,
                  tempData.length,
                  MediaQuery.of(context).size.width.floor(),
                  selectedThresholdChannelIdx,
                  isAverageSamples);
              */
              // List<Int16List> tempDataThreshold = List<Int16List>.generate(sublistArray.length, (index) => Int16List(sublistArray[index].length)..fillRange(0, sublistArray[index].length, 1000));
              List<Int16List> tempDataThreshold = sublistArray;
              // for (int i = 0; i < tempDataThreshold.length; i++) {
              //   Int16List element = tempDataThreshold[i];
              //   // int dateTimeTemp = (DateTime.now().millisecondsSinceEpoch % 1000000).floor();
              //   for (int j = 0; j < element.length; j++) {
              //     // element[j] = dateTimeTemp + j + i * 1000;
              //     // element[j] = sublistArray[i][j];
              //     // element[j] = ++counterThreshold;
              //     element[j] = 100;
              //   }
              //   // print("tempDataThreshold[$i] : ${tempDataThreshold[i]}");
              // }
              // print("tempDataThreshold0.length: ${tempDataThreshold[0].length}");
              // print("tempDataThreshold1.length: ${tempDataThreshold[1].length}");
              arr = processingUtil.processThresholdData(
                  tempDataThreshold,
                  tempDataThreshold.length,
                  MediaQuery.of(context).size.width.floor(),
                  selectedThresholdChannelIdx,
                  isAverageSamples);
            }
          }

          double playbackPercentage =
              (startPlaybackSeekSampleIdx + timerPlaybackLoadedStartIndex) /
                  (loadedMaxSamples);
          AdaptiveAreaState.horizontalDragX =
              playbackPercentage * AdaptiveAreaState.horizontalDragXFix;

          setState(() {});
        } catch (err) {
          print(
              "ERR: $err ||| $timerPlaybackLoadedEndIndex | $timerPlaybackLoadedStartIndex ");
        }
      });
    });
  }

  void callbackPlayButton(bool isPlay) async {
    // 1. UI state (no provider notify yet on play path so rebuild cannot run during setup)
    print("setGraphResumePlay PLAYBACK PAUSE BUTTON $isPlay");
    if (isPlay) {
      await _pauseLiveMonitorForFilePlayback();
    }
    _toPauseGraph = isPlay;
    GraphTemplate.isPlayerPaused = !isPlay;
    print(
        "setGraphResumePlay GraphTemplate.isPlayerPaused | SAMPLE RATEZ: $_sampleRate");

    // Notify UI only when pausing; when playing we notify after stream setup to avoid rebuild during setup (can trigger Platform access on web).
    // if (!isPlay) {
    Provider.of<GraphResumePlayProvider>(context, listen: false)
        .setGraphResumePlay(isPlay);
    // }

    // 2. SoLoud initialization (shared with live monitor — live streams paused above when playing)
    soloud ??= SoLoud.SoLoud.instance;
    if (!soloud!.isInitialized) {
      await soloud!.init(
        bufferSize: 512,
        sampleRate: _sampleRate,
        channels: SoLoud.Channels.mono,
      );
    }
    bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
    print("IS PLAY $isPlay");
    if (!isPlay) {
      // print("STOP SOUND | ${widget.channelCount} | ::: ${soloud?.getStreamTimeConsumed(loadedFileStreams[0]!)}");
      // Mark streams as ended before cancelling timer to prevent race conditions
      _isStreamEnded = true;
      timerPlaybackLoadedFile?.cancel();

      // Wait a brief moment to ensure any pending timer callbacks complete
      await Future.delayed(Duration(milliseconds: 100));

      if (soloud != null) {
        // double maxSamplesTime = loadedMaxSamples / _sampleRate * 1000;
        double sampleConsumed =
            (soloud?.getStreamTimeConsumed(loadedFileStreams[0]!))!
                    .inMilliseconds /
                2 *
                _sampleRate /
                1000;
        startPlaybackSeekSampleIdx += timerPlaybackLoadedStartIndex;
        startSeekSampleIdx = startPlaybackSeekSampleIdx;
        // startPlaybackSeekSampleIdx -= sampleDivider;
        print(
            "STOP SOUND | ${widget.channelCount} | ${(soloud?.getStreamTimeConsumed(loadedFileStreams[0]!))!.inMilliseconds} | ::: $sampleConsumed ::: $timerPlaybackLoadedStartIndex");
      }
      for (int i = 0; i < widget.channelCount; i++) {
        try {
          print(
              "STOP SOUND -- $i --| ${widget.channelCount} | ${(soloud?.getStreamTimeConsumed(loadedFileStreams[0]!))!.inMilliseconds} | :::");
          soloud?.setDataIsEnded(loadedFileStreams[i]!);
          soloud?.stop(loadedSoundHandles[i]!);
        } catch (e) {
          print("Error ending stream: $e");
        }
      }
      GraphTemplate.isLoadingFile = 2;
      // startPlaybackSeekSampleIdx += timerPlaybackLoadedStartIndex;
      // endSeekSampleIdx += timerPlaybackLoadedEndIndex;
      // timerPlaybackLoadedStartIndex = 0;
      // timerPlaybackLoadedEndIndex = 0;
      setState(() {});
    } else {
      loadedFileStreams.clear();
      _isStreamEnded = false; // Reset flag when creating new streams

      // print("ADDED FILE STREAMS : $_sampleRate || $startPlaybackSeekSampleIdx ||| $percentage || SCRUB: ${scrubNotifier.value}");
      // 3. SoLoud buffer stream setup
      print("widget.channelCount: ${widget.channelCount} ${_sampleRate}");
      for (int i = 0; i < widget.channelCount; i++) {
        if (!kIsWeb &&
            (Platform.isIOS ||
                Platform.isAndroid ||
                Platform.isMacOS ||
                Platform.isWindows)) {
          loadedFileStreams.add(soloud!.setBufferStream(
            // maxBufferSizeBytes: 1024 * 1024 * 10,
            // {Size} = {Sample Rate} * {Bytes per Sample} * {MONO CHANNEL} * {Desired Seconds} * {100  constant}
            bufferingType: SoLoud.BufferingType.released,
            sampleRate: _sampleRate,
            channels: SoLoud.Channels.mono,
            format: SoLoud.BufferType.s16le,
            onBuffering: (isBuffering, handle, time) async {
              print("IS BUFFERING $isBuffering $handle $time");
              if (context.mounted) {}
            },
          ));
        } else {
          loadedFileStreams.add(soloud!.setBufferStream(
            // maxBufferSizeBytes: 1024 * 1024 * 10,
            // {Size} = {Sample Rate} * {Bytes per Sample} * {MONO CHANNEL} * {Desired Seconds} * {100  constant}
            maxBufferSizeBytes: _sampleRate * 2 * 1 * 10,
            bufferingTimeNeeds: 0.05,
            bufferingType: SoLoud.BufferingType.released,
            sampleRate: _sampleRate,
            channels: SoLoud.Channels.mono,
            format: SoLoud.BufferType.s16le,
            onBuffering: (isBuffering, handle, time) async {
              print("IS BUFFERING $isBuffering $handle $time");
              if (context.mounted) {}
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
      double maxScreenSamples =
          ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate;
      double endSeekSample = 0; // (arrSamplesLength - startSeekSample).floor()
      print(
          "TIME 0 $startSeekSample | $maxScreenSamples | $loadedMaxSamples | $endSeekSample");
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
      Int16List arrSamples =
          Int16List(loadedMaxSamples.toInt() * widget.channelCount);
      // await GraphTemplate.nwbFileUtil?.seekElectricalSeries(arrSamples, arrSampleCount, loadedConfig, (startSeekSample).floor(), endSeekSample.floor(), 0, 1);
      // await GraphTemplate.nwbFileUtil?.seekElectricalSeries(arrSamples, arrSampleCount, loadedConfig, (startSeekSample).floor(), (loadedMaxSamples).floor(), 0, 1);
      print("======SEEK 1 ");

      // On web, seekElectricalSeries is async via callback, so we need to wait for data
      if (kIsWeb) {
        _pendingPlayback = true;
        _pendingPlaybackStartIdx = startPlaybackSeekSampleIdx;
        seekElectricalSeriesWebCompleter = Completer<Map<String, dynamic>>();

        // Filling SoLoud buffer with samples
        await GraphTemplate.nwbFileUtil?.seekElectricalSeriesWeb(
            currentLoadedFilePath,
            arrSamples,
            arrSampleCount,
            loadedConfig,
            (startPlaybackSeekSampleIdx).floor(),
            (loadedMaxSamples).floor(),
            0,
            widget.channelCount - 1);
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
              loadedArrSamples[i].setAll(
                  0,
                  arrSamples.sublist(
                      combinedIdx, combinedIdx + initialSampleCount.floor()));
              // loadedArrChannelCount.fillRange(0, totalChannelCount, initialSampleCount.floor());
              loadedArrChannelCount[i] = initialSampleCount.floor();
              combinedIdx += initialSampleCount.floor();
              // soloud!.addAudioDataStream(loadedFileStreams[i]!, loadedArrSamples[i].buffer.asUint8List());
            }
            // soloud!.setVisualizationEnabled(true);
          } catch (err) {
            print(
                "ERR: $err | arrSampleCount: $arrSampleCount -- channelCount: ${widget.channelCount}");
          }

          print("ADDED DATA STREAM Channel Count: ${widget.channelCount}");

          // Start playback timer (non-web path)

          loadedSoundHandles.clear();
          if (isAudioListen) {
            for (int i = 0; i < widget.channelCount; i++) {
              print(
                  "Initialize PLAY SOUND ${DateTime.now().millisecondsSinceEpoch}");
              soloud!.play(loadedFileStreams[i]!).then((soundHandle) {
                print(
                    "Start PLAY SOUND ${DateTime.now().millisecondsSinceEpoch}");
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
          print(
              "START SEEK SAMPLE INITIAL 0000 $startPlaybackSeekSampleIdx | ${arrSampleCount[0].floor()} == $loadedMaxSamples");
          if (startPlaybackSeekSampleIdx > 0 && arrSampleCount[0].floor() > 0) {
            int startInitialIndex =
                (startPlaybackSeekSampleIdx - maxScreenSamples.floor()).floor();
            startInitialIndex = startInitialIndex > 0 ? startInitialIndex : 0;
            // int endInitialIndex = startInitialIndex + (startSeekSample % maxScreenSamples.floor()).floor();
            int endInitialIndex = (startPlaybackSeekSampleIdx).floor();
            Int32List arrSampleCountInitial = Int32List(widget.channelCount);
            Int16List arrSamplesInitial =
                Int16List(endInitialIndex * widget.channelCount);
            print(
                "Start Initial Index: $startInitialIndex | End Initial Index: $endInitialIndex");

            // hardcode
            bool isAudioListen =
                context.read<DataStatusProvider>().isMicrophoneData;
            if (isAudioListen) {
              seekElectricalSeriesWebCompleter =
                  Completer<Map<String, dynamic>>();
              await GraphTemplate.nwbFileUtil?.seekElectricalSeriesWeb(
                  currentLoadedFilePath,
                  arrSamplesInitial,
                  arrSampleCountInitial,
                  loadedConfig,
                  startInitialIndex,
                  endInitialIndex,
                  0,
                  0);
              Map<String, dynamic> map =
                  await seekElectricalSeriesWebCompleter.future;
              // print("SEEK ELECTRICAL SERIES WEB COMPLETED2: $map | $startInitialIndex | $endInitialIndex");
              arrSamplesInitial = map['arrSamples'];
              arrSampleCountInitial = map['arrSampleCount'];
              var loadedConfigLocal = map['loadedConfig'];

              Int16List tempLoadedArrSamples =
                  Int16List(arrSampleCountInitial[0].floor());
              tempLoadedArrSamples.setAll(
                  0,
                  arrSamplesInitial.sublist(
                      0, arrSampleCountInitial[0].floor()));
              processingUtil.processMicrophoneData(
                  tempLoadedArrSamples.buffer.asUint8List());
              print(
                  "----> START SEEK SAMPLE INITIAL : $startInitialIndex |=| ${(startSeekSample % maxScreenSamples.floor()).floor()} | ${arrSampleCountInitial[0].floor()} |  ${tempLoadedArrSamples.length} |||| ${tempLoadedArrSamples.buffer.asUint8List().length}");
              microphoneUtil.micStream.value = Uint8List(0);
            } else {
              // FIX TOMORROW
              seekElectricalSeriesWebCompleter =
                  Completer<Map<String, dynamic>>();
              await GraphTemplate.nwbFileUtil?.seekElectricalSeriesWeb(
                  currentLoadedFilePath,
                  arrSamplesInitial,
                  arrSampleCountInitial,
                  loadedConfig,
                  startInitialIndex,
                  endInitialIndex,
                  0,
                  widget.channelCount - 1);
              Map<String, dynamic> map =
                  await seekElectricalSeriesWebCompleter.future;
              arrSamplesInitial = map['arrSamples'];
              arrSampleCountInitial = map['arrSampleCount'];
              var loadedConfigLocal = map['loadedConfig'];

              print(
                  "FIX TOMORROW: arrSamplesInitial: Widget Channel Length: ${widget.channelCount} ||| arrSamplesInitial: ${arrSamplesInitial.length} ||| arrSampleCountInitial: ${arrSampleCountInitial} ||| endInitialIndex: ${arrSampleCountInitial[0]}");
              List<Int16List> sublistArray = [];
              for (int i = 0; i < widget.channelCount; i++) {
                // HARDCODE!
                int samplesPerChannelLength = arrSampleCountInitial[0].floor();
                sublistArray.add(arrSamplesInitial.sublist(
                    i * samplesPerChannelLength,
                    (i + 1) * samplesPerChannelLength));
                // soloud!.addAudioDataStream(loadedFileStream!, sublistArray);
              }

              int channelIdx = 0;
              Int32List samplesCount = Int32List(sublistArray.length);
              Int16List flattenedList =
                  Int16List.fromList(sublistArray.expand((list) {
                samplesCount[channelIdx] = sublistArray[channelIdx].length;
                // print("SAMPLES COUNT: ${samplesCount[channelIdx]}");
                channelIdx++;
                return list;
              }).toList());

              processingUtil.processingSerialDataResult(
                  flattenedList, samplesCount, widget.channelCount);
              if (kIsWeb && mounted) {
                totalSampleCount += sublistArray[0].length;
                final provider =
                    Provider.of<GraphDataProvider>(context, listen: false);
                final drawSurfaceWidth =
                    MediaQuery.of(context).size.width.toInt();
                _scheduleSerialGraphPaint(provider, drawSurfaceWidth);
              }
            }
          } else {
            GraphTemplate.isLoadingFile = 4;
            // microphoneUtil.micStream.value = Uint8List(0);
          }

          // soloud!.addAudioDataStream(loadedFileStream!, loadedArrSamples.buffer.asUint8List());
        });
        return;
      } else {
        await GraphTemplate.nwbFileUtil?.seekElectricalSeries(
            currentLoadedFilePath,
            arrSamples,
            arrSampleCount,
            loadedConfig,
            (startPlaybackSeekSampleIdx).floor(),
            (loadedMaxSamples).floor(),
            0,
            widget.channelCount - 1);
      }

      int combinedIdx = 0;
      int totalChannelCount = loadedConfig[1];
      loadedArrSamples.clear();
      loadedArrChannelCount = (Int32List(widget.channelCount));
      for (int i = 0; i < widget.channelCount; i++) {
        // double initialSampleCount = arrSampleCount[i].floor() / totalChannelCount;
        double initialSampleCount = arrSampleCount[i].toDouble();
        loadedArrSamples.add(Int16List(initialSampleCount.floor()));
        loadedArrSamples[i].setAll(
            0,
            arrSamples.sublist(
                combinedIdx, combinedIdx + initialSampleCount.floor()));
        // loadedArrChannelCount.fillRange(0, totalChannelCount, initialSampleCount.floor());
        loadedArrChannelCount[i] = initialSampleCount.floor();
        combinedIdx += initialSampleCount.floor();
        if (!_isStreamEnded && loadedFileStreams[i] != null) {
          try {
            // if (isSpeakerChannelMuted[i]) {
            //   soloud!.addAudioDataStream(loadedFileStreams[i]!,
            //       (Int16List(loadedArrSamples[i].length)).buffer.asUint8List());
            // } else {
            //   soloud!.addAudioDataStream(loadedFileStreams[i]!,
            //       loadedArrSamples[i].buffer.asUint8List());
            // }
            soloud!.addAudioDataStream(
              loadedFileStreams[i]!,
              _loadedFilePcmBytes(loadedArrSamples[i]),
            );
          } catch (e) {
            // Stream may have been ended, stop trying to add data
            print("Error adding audio data to stream (may be ended): $e");
            _isStreamEnded = true;
          }
        }
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
      print(
          "START SEEK SAMPLE INITIAL 0000 $startPlaybackSeekSampleIdx ${arrSampleCount[0].floor()} == $loadedMaxSamples");
      if (startPlaybackSeekSampleIdx > 0 && arrSampleCount[0].floor() > 0) {
        // int startInitialIndex = (startPlaybackSeekSampleIdx ~/ maxScreenSamples.floor()) * maxScreenSamples.floor();
        int startInitialIndex =
            (startPlaybackSeekSampleIdx - maxScreenSamples.floor()).floor();
        startInitialIndex = startInitialIndex > 0 ? startInitialIndex : 0;
        // int endInitialIndex = startInitialIndex + (startSeekSample % maxScreenSamples.floor()).floor();
        int endInitialIndex = (startPlaybackSeekSampleIdx).floor();
        Int32List arrSampleCountInitial = Int32List(widget.channelCount);
        Int16List arrSamplesInitial =
            Int16List(endInitialIndex * widget.channelCount);
        print(
            "Start Initial Index: $startInitialIndex | End Initial Index: $endInitialIndex");

        bool isAudioListen =
            context.read<DataStatusProvider>().isMicrophoneData;
        if (isAudioListen) {
          await GraphTemplate.nwbFileUtil?.seekElectricalSeries(
              currentLoadedFilePath,
              arrSamplesInitial,
              arrSampleCountInitial,
              loadedConfig,
              startInitialIndex,
              endInitialIndex,
              0,
              0);
          Int16List tempLoadedArrSamples =
              Int16List(arrSampleCountInitial[0].floor());
          tempLoadedArrSamples.setAll(0,
              arrSamplesInitial.sublist(0, arrSampleCountInitial[0].floor()));
          processingUtil
              .processMicrophoneData(tempLoadedArrSamples.buffer.asUint8List());
          print(
              "----> START SEEK SAMPLE INITIAL : $startInitialIndex |=| ${(startSeekSample % maxScreenSamples.floor()).floor()} | ${arrSampleCountInitial[0].floor()} |  ${tempLoadedArrSamples.length} |||| ${tempLoadedArrSamples.buffer.asUint8List().length}");
          microphoneUtil.micStream.value = Uint8List(0);
        } else {
          // FIX TOMORROW
          await GraphTemplate.nwbFileUtil?.seekElectricalSeries(
              currentLoadedFilePath,
              arrSamplesInitial,
              arrSampleCountInitial,
              loadedConfig,
              startInitialIndex,
              endInitialIndex,
              0,
              widget.channelCount - 1);
          print(
              "FIX TOMORROW: arrSamplesInitial: ${arrSamplesInitial.length} ||| arrSampleCountInitial: ${arrSampleCountInitial} ||| endInitialIndex: ${arrSampleCountInitial[0]}");
          List<Int16List> sublistArray = [];
          for (int i = 0; i < widget.channelCount; i++) {
            int samplesPerChannelLength = arrSampleCountInitial[i].floor();
            sublistArray.add(arrSamplesInitial.sublist(
                i * samplesPerChannelLength,
                (i + 1) * samplesPerChannelLength));
            // soloud!.addAudioDataStream(loadedFileStream!, sublistArray);
          }

          int channelIdx = 0;
          Int32List samplesCount = Int32List(sublistArray.length);
          Int16List flattenedList =
              Int16List.fromList(sublistArray.expand((list) {
            samplesCount[channelIdx] = sublistArray[channelIdx].length;
            // print("SAMPLES COUNT: ${samplesCount[channelIdx]}");
            channelIdx++;
            return list;
          }).toList());

          processingUtil.processingSerialDataResult(
              flattenedList, samplesCount, widget.channelCount);
        }
      } else {
        GraphTemplate.isLoadingFile = 4;
        // microphoneUtil.micStream.value = Uint8List(0);
      }
      // soloud!.addAudioDataStream(loadedFileStream!, loadedArrSamples.buffer.asUint8List());
    }
  }

  void stopCurrentPlaying() {
    try {
      _isStreamEnded = true; // Mark streams as ended
      if (soloud != null) {
        print("listenToMicrophone soloud != null ");
        for (int i = 0; i < loadedSoundHandles.length; i++) {
          soloud?.stop(loadedSoundHandles[i]!);
        }
        soloud = null;
      } else {
        print("listenToMicrophone soloud == null ");
      }

      // isSpeakerChannelMuted.fillRange(0, isSpeakerChannelMuted.length, true);
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
      recordingNotifier.value = [0, 0];
      soloud = null;
      loadedFileStreams = [];
      loadedSoundHandles = [];
      isOpeningFile = false;
      getData = null;
      periodicTimerSerial?.cancel();
    } catch (err) {
      print("er listenToMicrophone");
      print(err);
    }
  }

  serialWebButton() {
    return kIsWeb
        ? isRecording != 0 || isOpeningFile
            ? SizedBox()
            : ElevatedButton(
                // elevation: 2,
                // shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(width: 2, color: Colors.grey)),
                // backgroundColor: SoftwareColors.kButtonBackGroundColor,
                style: ElevatedButton.styleFrom(
                  shape: const CircleBorder(), // This makes the shape circular
                  padding: const EdgeInsets.all(
                      20), // Controls the size of the button
                  backgroundColor:
                      SoftwareColors.kButtonBackGroundColor, // Button color
                ),
                onPressed: () async {
                  if (_isSerialWebButtonEnabled) {
                    _isSerialWebButtonEnabled = false;
                    _serialUtil.closePort();
                    isDeviceConnect = true;
                    isDeviceSelected = false;
                    isSerialDeviceFound = false;
                    _isDataIdentified = false;

                    GraphDataProvider graphDataProvider =
                        Provider.of<GraphDataProvider>(context, listen: false);
                    listenToMicrophone(1, graphDataProvider);
                    streamScrubBuilderController.add(Random().nextInt(100000));
                    isSerialDeviceFound = false;
                    return;
                  }
                  _isSerialWebButtonEnabled = true;
                  setState(() {});
                  print(
                      "serialWebButtonPressed ::: $_baudRate isDeviceConnect: $isDeviceConnect");
                  serialWebButtonPressed(_baudRate);
                },
                child: Row(
                  children: [
                    Icon(
                      Icons.usb,
                      size: 25,
                      color: _isSerialWebButtonEnabled
                          ? Colors.yellow
                          : SoftwareColors.kButtonColor,
                    )
                  ],
                ),
              )
        : Container();
  }

  void resetRecordingState(widgetContext) {
    if (isRecording == 1) {
      if (kIsWeb) {
        GraphTemplate.nwbFileUtil?.addElectricalSeries(
            Int16List(0), Int32List(0), 0, visibleChannelCount, 1);
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
                publicPath = await GraphTemplate.nwbFileUtil
                    ?.makeFilePublic(recordedFilePath!);
              }
              // ScaffoldMessenger.of(widgetContext).showSnackBar(SnackBar(
              //   content: Text("File recorded successfully: $publicPath"),
              //   duration: Duration(seconds: 7),
              // ));
              ScaffoldMessenger.of(widgetContext).showSnackBar(SnackBar(
                // content: Text("File recorded successfully: $publicPath"),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.transparent,
                content: getSavedRecordingBanner(publicPath),
                width: MediaQuery.of(widgetContext).size.width /
                    3, // Fixed width helps it look like a dialog/toast
                margin: EdgeInsets.only(
                  bottom: MediaQuery.of(widgetContext).size.height / 2 -
                      30, // Adjust -25 based on approximate SnackBar height
                ),
                duration: Duration(seconds: 7),
              ));
            } else {
              String recordedFilePathProcessed = "~/Downloads/" +
                  recordedFilePath!
                      .substring(recordedFilePath!.lastIndexOf("/") + 1);

              ScaffoldMessenger.of(widgetContext).showSnackBar(SnackBar(
                // content: Text("File recorded successfully: $recordedFilePath"),
                // content: getSavedRecordingBanner(recordedFilePath),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.transparent,
                content: getSavedRecordingBanner(recordedFilePathProcessed),
                margin: EdgeInsets.only(
                  bottom: MediaQuery.of(widgetContext).size.height / 2 -
                      30, // Adjust -25 based on approximate SnackBar height
                ),
                duration: Duration(seconds: 7),
              ));
            }
          } else {
            // Web platform - file download is handled automatically
            // ScaffoldMessenger.of(widgetContext).showSnackBar(SnackBar(content: Text("File recorded successfully: $recordedFilePath"), duration: Duration(seconds: 7),));
          }
        }
      }
      setState(() {});
    });
  }

  serialErrorCallback(int channelCount, provider) {
    print("SERIAL ERROR CALLBACK $channelCount");
    if (channelCount >= 1) {
      if (!mounted) return;
      _resetSerialPipelineAfterBaudChange();
      isDeviceConnect = true;
      isDeviceSelected = false;
      _isDataIdentified = false;
      isSerialDeviceFound = false;
      if (deviceTimer != null) {
        deviceTimer?.cancel();
        deviceTimer = null;
      }
      _isDeviceTimerRunning = false;
      // return;
    }
    if (isRecording > 0) {
      resetRecordingState(context);
    }
    print("End Reset Recording State");
    if (!kIsWeb) {
      final provider = Provider.of<GraphDataProvider>(context, listen: false);
      Future.delayed(Duration(seconds: 1), () {
        print("Listen To Microphone Serial Error");
        listenToMicrophone(1, provider);
      });
    }
  }

  void setSerialHpf(bool active) {
    String sstm;
    if (active) {
      sstm = "hpfon:2;hpfon:1;\n";
    } else {
      sstm = "hpfoff:2;hpfoff:1;\n";
    }
    _serialUtil.writeToPort(
        bytesMessage: Uint8List.fromList(utf8.encode(sstm)),
        address: _availablePorts.last);
  }

  void setSerialGain(bool active) {
    String sstm;
    if (active) {
      sstm = "gainon:1;gainon:2;";
    } else {
      sstm = "gainoff:1;gainoff:2;";
    }
    print("SSTM : $sstm");
    _serialUtil.writeToPort(
        bytesMessage: Uint8List.fromList(utf8.encode(sstm)),
        address: _availablePorts.last);
  }

  buildSerialUsageTypeButton(String s, int channelIdx) {
    bool isSelected = serialUsageType.contains(s);
    print(
        "SELECTED Serial usage type : $serialUsageType --VS-- $s == $isSelected");
    ButtonStyle style = ElevatedButton.styleFrom(
      // Toggle colors based on selection
      backgroundColor: isSelected ? Colors.blue : Colors.grey[300],
      foregroundColor: isSelected ? Colors.white : Colors.black,
    );
    // print("COMPARE: $serialUsageType -- $s == $isSelected");
    List<int> channelIndices = List<int>.generate(
        widget.channelCount, (index) => index == channelIdx ? index : -1);
    double sublabelFontSize = 10;

    switch (s) {
      case "ECG":
        Color? iconColor = isSelected ? Color(0xFFff805f) : Color(0xFF585858);
        // print(
        //     "ECG ICON COLOR: $iconColor -- $isSelected || S : $s ++ SerialUsageType : $serialUsageType");
        return Container(
            padding: EdgeInsets.fromLTRB(10, 10, 10, 10),
            margin: EdgeInsets.fromLTRB(10, 0, 10, 20),
            decoration: BoxDecoration(
              // color: isSelected ? Color(0xFF3c3c3c) : Colors.transparent,
              color: isSelected
                  ? Color.fromARGB(255, 70, 70, 70)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () {
                    print("DETECTOR ECG");
                    serialUsageType = "ECG";
                    arrFilterUsageTypeChannel[channelIdx] = serialUsageType;
                    startValue = 1;
                    endValue = 100;
                    setupFilterValues(
                        channelIndices, [startValue, endValue, 0]);
                  },
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: iconColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: iconColor, width: 30),
                        ),
                      ),
                      Positioned.fill(
                        child: Center(
                          child: SvgPicture.asset(
                            'assets/icons/config_ecg_off.svg',
                            width: 60,
                            height: 60,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 5,
                ),
                Text(
                  "ECG",
                  style: TextStyle(fontSize: 14, color: Colors.white),
                ),
                SizedBox(
                  height: 3,
                ),
                Text(
                  "Heartbeats",
                  style: TextStyle(
                      color: Color(0xFF707070), fontSize: sublabelFontSize),
                ),
                getSelectedNotchWidget(isSelected, iconColor),
              ],
            ));
        break;
      case "EEG":
        Color? iconColor = isSelected ? Color(0xFF0093ff) : Color(0xFF585858);
        return Container(
            padding: EdgeInsets.fromLTRB(10, 10, 10, 10),
            margin: EdgeInsets.fromLTRB(10, 0, 10, 20),
            decoration: BoxDecoration(
              color: isSelected ? Color(0xFF3c3c3c) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () {
                    print("DETECTOR EEG");
                    serialUsageType = "EEG";
                    arrFilterUsageTypeChannel[channelIdx] = serialUsageType;
                    startValue = 0;
                    endValue = 50;
                    setupFilterValues(
                        channelIndices, [startValue, endValue, 1]);
                  },
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: iconColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: iconColor, width: 30),
                        ),
                      ),
                      Positioned.fill(
                        child: Center(
                          child: SvgPicture.asset(
                            'assets/icons/config_eeg_off.svg',
                            width: 60,
                            height: 60,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 5,
                ),
                Text("EEG",
                    style: TextStyle(fontSize: 14, color: Colors.white)),
                SizedBox(
                  height: 3,
                ),
                Text(
                  "Brainwaves",
                  style: TextStyle(
                      color: Color(0xFF707070), fontSize: sublabelFontSize),
                ),
                getSelectedNotchWidget(isSelected, iconColor),
              ],
            ));
        break;
      case "EMG":
        Color? iconColor = isSelected ? Color(0xFFffc600) : Color(0xFF585858);
        // print(
        //     "EMG ICON COLOR: $iconColor -- $isSelected || S : $s ++ SerialUsageType : $serialUsageType");
        return Container(
            padding: EdgeInsets.fromLTRB(10, 10, 10, 10),
            margin: EdgeInsets.fromLTRB(10, 0, 10, 10),
            decoration: BoxDecoration(
              color: isSelected ? Color(0xFF3c3c3c) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () {
                    print("DETECTOR EMG");
                    serialUsageType = "EMG";
                    arrFilterUsageTypeChannel[channelIdx] = serialUsageType;
                    startValue = 70;
                    endValue = 2500;
                    setupFilterValues(
                        channelIndices, [startValue, endValue, 2]);
                  },
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: iconColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: iconColor, width: 30),
                        ),
                      ),
                      Positioned.fill(
                        child: Center(
                          child: SvgPicture.asset(
                            'assets/icons/config_emg_off.svg',
                            width: 60,
                            height: 60,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 5,
                ),
                Text(
                  "EMG",
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
                SizedBox(
                  height: 3,
                ),
                Text(
                  "Muscle signals",
                  style: TextStyle(
                      fontSize: sublabelFontSize, color: Color(0xFF707070)),
                ),
                getSelectedNotchWidget(isSelected, iconColor),
              ],
            ));
        break;
      case "Plant":
        Color? iconColor = isSelected ? Color(0xFF00aa50) : Color(0xFF585858);
        return Container(
            padding: EdgeInsets.fromLTRB(10, 10, 10, 10),
            margin: EdgeInsets.fromLTRB(10, 0, 10, 20),
            decoration: BoxDecoration(
              color: isSelected ? Color(0xFF3c3c3c) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () {
                    print("DETECTOR Plant");
                    serialUsageType = "Plant";
                    arrFilterUsageTypeChannel[channelIdx] = serialUsageType;
                    startValue = 0;
                    endValue = 5;
                    setupFilterValues(
                        channelIndices, [startValue, endValue, 3]);
                  },
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: iconColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: iconColor, width: 30),
                        ),
                      ),
                      Positioned.fill(
                        child: Center(
                          child: SvgPicture.asset(
                            'assets/icons/config_plant_off.svg',
                            width: 60,
                            height: 60,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 5,
                ),
                Text(
                  "Plant",
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
                SizedBox(
                  height: 3,
                ),
                Text(
                  "Plant signals",
                  style: TextStyle(
                      fontSize: sublabelFontSize, color: Color(0xFF707070)),
                ),
                getSelectedNotchWidget(isSelected, iconColor),
              ],
            ));
        break;
      case "Neuron":
        print("NEURON DATA");
        Color? iconColor = isSelected ? Color(0xFFd205a5) : Color(0xFF585858);
        return Container(
            padding: EdgeInsets.fromLTRB(10, 10, 10, 10),
            margin: EdgeInsets.fromLTRB(10, 0, 10, 20),
            decoration: BoxDecoration(
              color: isSelected ? Color(0xFF3c3c3c) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () {
                    print("DETECTOR Neuron");
                    serialUsageType = "Neuron";
                    arrFilterUsageTypeChannel[channelIdx] = serialUsageType;
                    startValue = 70;
                    endValue = _sampleRate / 2;
                    setupFilterValues(
                        channelIndices, [startValue, endValue, 4]);
                  },
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: iconColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: iconColor, width: 30),
                        ),
                      ),
                      Positioned.fill(
                        child: Center(
                          child: SvgPicture.asset(
                            'assets/icons/config_neuron_off.svg',
                            width: 60,
                            height: 60,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 5,
                ),
                Text(
                  "Neuron",
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
                SizedBox(
                  height: 3,
                ),
                Text(
                  "Neuron signals",
                  style: TextStyle(
                      fontSize: sublabelFontSize, color: Color(0xFF707070)),
                ),
                getSelectedNotchWidget(isSelected, iconColor),
              ],
            ));
        break;
      case "Custom":
        Color? iconColor = isSelected ? Color(0xFFdbdbdb) : Color(0xFF707070);
        return Container(
            padding: EdgeInsets.fromLTRB(10, 10, 10, 10),
            margin: EdgeInsets.fromLTRB(10, 0, 10, 20),
            decoration: BoxDecoration(
              color: isSelected ? Color(0xFF3c3c3c) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () {
                    print("DETECTOR Custom");
                    serialUsageType = "Custom";
                    arrFilterUsageTypeChannel[channelIdx] = serialUsageType;
                    startValue = 70;
                    endValue = _sampleRate / 2;
                    setupFilterValues(
                        channelIndices, [startValue, endValue, 5]);
                  },
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: iconColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: iconColor, width: 30),
                        ),
                      ),
                      Positioned.fill(
                        child: Center(
                          child: SvgPicture.asset(
                            'assets/icons/button_custom.svg',
                            width: 32,
                            height: 32,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 5,
                ),
                Text(
                  "Custom",
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
                SizedBox(
                  height: 3,
                ),
                Text(
                  "Set Range",
                  style: TextStyle(
                      fontSize: sublabelFontSize, color: Color(0xFF707070)),
                ),
                getSelectedNotchWidget(isSelected, iconColor),
              ],
            ));
      default:
        return Container();
    }
  }

  _mutingSpeakers() {
    bool isAudio = context.read<DataStatusProvider>().isMicrophoneData;
    var provider = context.read<ChannelFilterProvider>();
    bool currentFilterEnabled = isAudio
        ? provider.getAudioFilter(customizeDetailChannelIdx)
        : provider.getSerialFilter(customizeDetailChannelIdx);
    return Container(
      margin: EdgeInsets.only(top: 10),
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color(0xFF2e2e2e),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Checkbox(
              value: isSpeakerChannelMuted[customizeDetailChannelIdx],
              onChanged: (flag) {
                if (flag != null) {
                  isSpeakerChannelMuted[customizeDetailChannelIdx] = flag;
                  _processedSamplePlayer?.setChannelMuted(
                    customizeDetailChannelIdx,
                    flag,
                  );
                  _processedSamplePlayer?.enabled =
                      _liveMonitorAnyChannelAudible();
                  if (_liveMonitorAnyChannelAudible()) {
                    unawaited(_ensureLiveMonitorPlayer());
                  }
                }
                setState(() {});
              }),
          SizedBox(width: 5),
          Icon(CupertinoIcons.speaker_2, color: Colors.white),
          SizedBox(width: 5),
          Text("Mute Speakers", style: TextStyle(color: Colors.white)),
          Spacer(),
          Checkbox(
              value: currentFilterEnabled,
              onChanged: (flag) async {
                int idx = customizeDetailChannelIdx;
                if (isAudio) {
                  provider.setAudioFilter(idx, !currentFilterEnabled);
                } else {
                  provider.setSerialFilter(idx, !currentFilterEnabled);
                  print("setSerialFilter: $idx | ${!currentFilterEnabled}");
                }
                await processingUtil.setChannelFilterEnabled(idx, isAudio);
                setState(() {});
              }),
          SizedBox(width: 5),
          Icon(Icons.filter_alt_outlined, color: Colors.white),
          Text("Channel Filter", style: TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  getSelectedNotchWidget(bool isSelected, Color iconColor) {
    return SizedBox.shrink();
    return isSelected
        ? Stack(
            children: [
              SizedBox(
                height: 20,
                width: 100,
                child: CustomPaint(
                  painter: HumpCustomPainter(),
                ),
              ),
              Positioned(
                top: 5,
                left: 48,
                child: Center(
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: iconColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              )
            ],
          )
        : SizedBox(
            height: 20,
            width: 100,
          );
  }

  getSavedRecordingBanner(String? publicPath) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF4A4A4A), // Dark grey background
        borderRadius: BorderRadius.circular(40), // Large rounded corners
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.save_outlined, // Floppy disk style icon
            color: Colors.white,
            size: 28,
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saved recording to',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  publicPath ?? "",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _resetSerialIngestPipeline() {
    _serialIngestQueue.clear();
    _serialIngestDraining = false;
    _serialDisplayDeferred = false;
    _serialGraphPaintInFlight = false;
    _lastSerialDisplayAt = null;
  }

  void _registerWebLivePlaybackListener() {
    if (!kIsWeb) return;
    ProcessingUtil.webLivePlaybackListener = _onWebLivePlaybackChunks;
  }

  /// Live monitor and loaded-file playback share [SoLoud.instance]; stop live streams before file play.
  Future<void> _pauseLiveMonitorForFilePlayback() async {
    if (_processedSamplePlayer?.isActive ?? false) {
      await _processedSamplePlayer!.stop();
    }
  }

  /// PCM for opened-file playback (ignores "Mute Speakers" — that applies to live monitor only).
  Uint8List _loadedFilePcmBytes(Int16List samples) {
    return samples.buffer.asUint8List(
      samples.offsetInBytes,
      samples.lengthInBytes,
    );
  }

  void _syncLiveMonitorSpeakerMutes() {
    final player = _processedSamplePlayer;
    if (player == null) return;
    final limit = widget.channelCount.clamp(1, isSpeakerChannelMuted.length);
    for (var i = 0; i < limit; i++) {
      player.setChannelMuted(i, isSpeakerChannelMuted[i]);
    }
    player.enabled = _liveMonitorAnyChannelAudible();
  }

  bool _liveMonitorAnyChannelAudible() {
    final channelLimit =
        widget.channelCount.clamp(1, isSpeakerChannelMuted.length);
    for (var i = 0; i < channelLimit; i++) {
      if (!isSpeakerChannelMuted[i]) return true;
    }
    return false;
  }

  bool _shouldRunLiveMonitor() {
    if (!mounted || GraphTemplate.isPlayerPaused) return false;
    if (GraphTemplate.isLoadingFile != 0) return false;
    return true;
  }

  /// Starts or reconfigures SoLoud for live mic or serial monitoring.
  Future<void> _ensureLiveMonitorPlayer({int? channelCount}) async {
    if (!mounted) return;

    final channels = channelCount ?? widget.channelCount;
    if (channels < 1 || _sampleRate < 1) return;

    _processedSamplePlayer ??= ProcessedSamplePlayer(
      lowLatencyBufferSeconds: 0.01,
    );

    final sameConfig = _liveMonitorSampleRate == _sampleRate &&
        _liveMonitorChannelCount == channels &&
        _processedSamplePlayer!.isActive;
    if (sameConfig) {
      _syncLiveMonitorSpeakerMutes();
      return;
    }

    if (_processedSamplePlayer!.isActive) {
      await _processedSamplePlayer!.stop();
    }
    await _processedSamplePlayer!.init(
      sampleRate: _sampleRate,
      channelCount: channels,
    );
    await _processedSamplePlayer!.start();
    _liveMonitorSampleRate = _sampleRate;
    _liveMonitorChannelCount = channels;
    _syncLiveMonitorSpeakerMutes();
  }

  void _onWebLivePlaybackChunks(List<Int16List> chunks) {
    if (!mounted || chunks.isEmpty) return;
    if (!_shouldRunLiveMonitor()) return;
    if (ProcessingUtil.webLivePlaybackListener != _onWebLivePlaybackChunks) {
      _registerWebLivePlaybackListener();
    }
    unawaited(() async {
      await _ensureLiveMonitorPlayer(channelCount: chunks.length);
      if (!_liveMonitorAnyChannelAudible()) return;
      _processedSamplePlayer?.enqueueProcessedChunk(chunks);
    }());
  }

  void _enqueueLiveSerialAudio(List<Int16List> samples) {
    if (kIsWeb) return;
    if (!_shouldRunLiveMonitor() || samples.isEmpty) return;
    if (context.read<DataStatusProvider>().isMicrophoneData) return;
    _processedSamplePlayer?.enqueueProcessedChunk(samples);
  }

  void _injectSerialSamples(List<Int16List> channels) {
    var channelIdx = 0;
    final samplesCount = Int32List(channels.length);
    final flattenedList = Int16List.fromList(channels.expand((list) {
      samplesCount[channelIdx] = channels[channelIdx].length;
      channelIdx++;
      return list;
    }).toList());
    processingUtil.processingSerialDataResult(
        flattenedList, samplesCount, widget.channelCount);
  }

  /// Loaded NWB playback: samples are already decoded (not raw UART bytes).
  void _enqueueSerialDecodedIngest(
    List<Int16List> channels,
    GraphDataProvider provider,
    int drawSurfaceWidth,
  ) {
    if (!mounted || channels.isEmpty || channels[0].isEmpty) return;
    _injectSerialSamples(channels);
    if (isThresholdingButton && kIsWeb) {
      arr = [_effectiveSerialThresholdSpan()];
    }
    totalSampleCount += channels[0].length;
    _scheduleSerialGraphPaint(provider, drawSurfaceWidth);
  }

  int _effectiveSerialThresholdSpan() {
    if (kIsWeb && processingUtil.thresholdingArraylength > 0) {
      return processingUtil.thresholdingArraylength;
    }
    if (arr.isNotEmpty && arr[0] > 0) {
      return arr[0];
    }
    return (displayTimeMs * 0.001 * _sampleRate).floor().clamp(1, 1 << 30);
  }

  void _enqueueSerialIngest(
    Uint8List event,
    GraphDataProvider provider,
    int drawSurfaceWidth, {
    bool paintFromZero = false,
    List<Int16List>? decodedChannels,
  }) {
    if (decodedChannels != null) {
      _enqueueSerialDecodedIngest(decodedChannels, provider, drawSurfaceWidth);
      return;
    }
    if (event.isEmpty) return;
    _serialPaintFromZero = paintFromZero;
    _serialIngestQueue.add(event);
    if (_serialIngestDraining) return;
    _serialIngestDraining = true;
    unawaited(_drainSerialIngestQueue(provider, drawSurfaceWidth));
  }

  /// One UART chunk per drain step — avoids merging backlog into a single late playback burst.
  Uint8List? _takeNextSerialChunk() {
    if (_serialIngestQueue.isEmpty) return null;
    return _serialIngestQueue.removeAt(0);
  }

  Future<void> _drainSerialIngestQueue(
    GraphDataProvider provider,
    int drawSurfaceWidth,
  ) async {
    try {
      while (_serialIngestQueue.isNotEmpty) {
        if (!mounted) return;
        final batch = _takeNextSerialChunk();
        if (batch == null || batch.isEmpty) continue;

        final samples = await processingUtil.processSerialData(
          batch,
          displayTimeMs.toInt(),
          deviceType,
          drawSurfaceWidth,
          provider,
        );
        // Audio first; do not await graph paint (that was blocking the next chunk).
        _enqueueLiveSerialAudio(samples);
        _accumulateSerialSamplesForDisplay(samples, drawSurfaceWidth);
        _scheduleSerialGraphPaint(provider, drawSurfaceWidth);
      }
    } finally {
      _serialIngestDraining = false;
      if (mounted && _serialDisplayDeferred) {
        await _flushDeferredSerialDisplay(provider, drawSurfaceWidth);
      }
      if (mounted && _serialIngestQueue.isNotEmpty && !_serialIngestDraining) {
        _serialIngestDraining = true;
        unawaited(_drainSerialIngestQueue(provider, drawSurfaceWidth));
      }
    }
  }

  void _handleSerialRecording(List<Int16List> samples) {
    var channelIdx = 0;
    final samplesCount = Int32List(samples.length);
    final flattenedList = Int16List.fromList(samples.expand((list) {
      samplesCount[channelIdx] = samples[channelIdx].length;
      channelIdx++;
      return list;
    }).toList());
    if (isRecording == 1) {
      if (!kIsWeb) {
        GraphTemplate.nwbFileUtil?.addElectricalSeries(
            flattenedList, samplesCount, 0, samples.length, 0);
      }
      recordingNotifier.value = [
        recordingStartTime,
        DateTime.now().millisecondsSinceEpoch
      ];
    } else if (isRecording == 2) {
      if (!kIsWeb) {
        GraphTemplate.nwbFileUtil?.addElectricalSeries(
            flattenedList, samplesCount, 0, samples.length, 1);
      }
      recordingNotifier.value = [
        recordingStartTime,
        DateTime.now().millisecondsSinceEpoch
      ];
      isRecording = 0;
    }
  }

  void _accumulateSerialSamplesForDisplay(
    List<Int16List> samples,
    int drawSurfaceWidth,
  ) {
    if (!mounted || samples.isEmpty) return;

    _handleSerialRecording(samples);

    if (isThresholdingButton) {
      if (kIsWeb) {
      } else {
        final selectedChannel =
            context.read<ThresholdStatusProvider>().selectedThresholdChannel;
        const isAverageSamples = true;
        arr = processingUtil.processThresholdData(samples, samples.length,
            drawSurfaceWidth, selectedChannel, isAverageSamples);
      }
    }

    totalSampleCount += samples[0].length;
  }

  void _scheduleSerialGraphPaint(
    GraphDataProvider provider,
    int drawSurfaceWidth,
  ) {
    if (!mounted) return;
    if (!_shouldPaintSerialGraphNow()) {
      _serialDisplayDeferred = true;
      return;
    }
    if (_serialGraphPaintInFlight) {
      _serialDisplayDeferred = true;
      return;
    }
    _serialGraphPaintInFlight = true;
    unawaited(_runSerialGraphPaint(provider, drawSurfaceWidth));
  }

  Future<void> _runSerialGraphPaint(
    GraphDataProvider provider,
    int drawSurfaceWidth,
  ) async {
    try {
      do {
        if (!mounted) return;
        if (!_shouldPaintSerialGraphNow()) {
          _serialDisplayDeferred = true;
          return;
        }
        totalSampleCount = 0;
        _serialDisplayDeferred = false;
        _lastSerialDisplayAt = DateTime.now();
        await _paintLiveSerialGraph(provider, drawSurfaceWidth);
        if (mounted) {
          provider.inputListener(Uint8List(0));
        }
      } while (
          mounted && _serialDisplayDeferred && _shouldPaintSerialGraphNow());
    } finally {
      _serialGraphPaintInFlight = false;
      if (mounted && _serialDisplayDeferred && _shouldPaintSerialGraphNow()) {
        _scheduleSerialGraphPaint(provider, drawSurfaceWidth);
      }
    }
  }

  Future<void> _onSerialSamplesIngested(
    List<Int16List> samples,
    GraphDataProvider provider,
    int drawSurfaceWidth,
  ) async {
    _accumulateSerialSamplesForDisplay(samples, drawSurfaceWidth);
    _scheduleSerialGraphPaint(provider, drawSurfaceWidth);
  }

  bool _shouldPaintSerialGraphNow() {
    if (totalSampleCount <= sampleCountToDisplay) return false;
    final last = _lastSerialDisplayAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= _minSerialDisplayInterval;
  }

  Future<void> _flushDeferredSerialDisplay(
    GraphDataProvider provider,
    int drawSurfaceWidth,
  ) async {
    if (!mounted || !_serialDisplayDeferred) return;
    if (!_shouldPaintSerialGraphNow()) return;

    totalSampleCount = 0;
    _serialDisplayDeferred = false;
    _lastSerialDisplayAt = DateTime.now();
    await _paintLiveSerialGraph(provider, drawSurfaceWidth);
    if (mounted) {
      provider.inputListener(Uint8List(0));
    }
  }

  ({int fromSample, int toSample}) _serialFileDisplaySampleRange() {
    final maxSamples =
        (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
    var toSample = (maxSamples + bufferPaddingLeft).toInt();
    toSample = min(maxSamples, toSample);
    final fromSample = (toSample - displayTimeMs * 0.001 * _sampleRate).toInt();
    return (fromSample: fromSample, toSample: toSample);
  }

  ({int fromSample, int toSample}) _serialFileThresholdDisplaySampleRange() {
    final span = _effectiveSerialThresholdSpan();
    final displayTimeDivision = (displayTimeMs / 10000);
    final gap = (span * (1 - displayTimeDivision));
    final maxSamples =
        (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
    final toSample = maxSamples - (gap / 2).floor();
    final fromSample = toSample - span + (gap).floor();
    return (fromSample: fromSample, toSample: toSample);
  }

  Future<void> _paintSerialFileGraph(
    GraphDataProvider provider,
    int drawSurfaceWidth,
  ) async {
    final range = isThresholdingButton
        ? _serialFileThresholdDisplaySampleRange()
        : _serialFileDisplaySampleRange();
    DraggableGraph.startPositionIdx = range.fromSample;
    DraggableGraph.endPositionIdx = range.toSample;
    await processingUtil.processDisplaySerialData(
      displayTimeMs.toInt(),
      deviceType,
      drawSurfaceWidth,
      provider,
      range.fromSample,
      range.toSample,
    );
  }

  Future<void> _paintLiveSerialGraph(
    GraphDataProvider provider,
    int drawSurfaceWidth,
  ) async {
    if (isOpeningFile) {
      await _paintSerialFileGraph(provider, drawSurfaceWidth);
      return;
    }

    if (isThresholdingButton) {
      final range = _serialFileThresholdDisplaySampleRange();
      DraggableGraph.startPositionIdx = range.fromSample;
      DraggableGraph.endPositionIdx = range.toSample;
      await processingUtil.processDisplaySerialData(
          displayTimeMs.toInt(),
          deviceType,
          drawSurfaceWidth,
          provider,
          range.fromSample,
          range.toSample);
      return;
    }

    final maxSamples =
        (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
    final maxDisplaySamples = (displayTimeMs * 0.001 * _sampleRate).floor();
    if (_serialPaintFromZero) {
      DraggableGraph.startPositionIdx = 0;
      DraggableGraph.endPositionIdx = maxDisplaySamples;
      await processingUtil.processDisplaySerialData(displayTimeMs.toInt(),
          deviceType, drawSurfaceWidth, provider, 0, maxDisplaySamples);
    } else {
      DraggableGraph.startPositionIdx = maxSamples - maxDisplaySamples;
      DraggableGraph.endPositionIdx = maxSamples;
      await processingUtil.processDisplaySerialData(displayTimeMs.toInt(),
          deviceType, drawSurfaceWidth, provider, 0, maxDisplaySamples);
    }
  }

  Future<void> _maybeTriggerPausedDragDisplay(
    GraphDataProvider provider,
    int drawSurfaceWidth,
  ) async {
    totalSampleCount += 2;
    if (!_shouldPaintSerialGraphNow()) {
      _serialDisplayDeferred = true;
      return;
    }

    totalSampleCount = 0;
    _serialDisplayDeferred = false;
    _lastSerialDisplayAt = DateTime.now();

    final maxSamples =
        (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
    var toSample = (maxSamples + bufferPaddingLeft).toInt();
    toSample = min(maxSamples, toSample);
    var fromSample = (toSample - displayTimeMs * 0.001 * _sampleRate).toInt();
    DraggableGraph.startPositionIdx = fromSample;
    DraggableGraph.endPositionIdx = toSample;

    if (isThresholdingButton) {
      final displayTimeDivision = (displayTimeMs / 10000);
      final gap = (arr[0] * (1 - displayTimeDivision));
      toSample = maxSamples - (gap / 2).floor();
      fromSample = toSample - arr[0] + (gap).floor();
      await processingUtil.processDisplaySerialData(displayTimeMs.toInt(),
          deviceType, drawSurfaceWidth, provider, fromSample, toSample);
    } else {
      await processingUtil.processDisplaySerialData(displayTimeMs.toInt(),
          deviceType, drawSurfaceWidth, provider, fromSample, toSample);
    }
  }

  void callSerialDataSubscription() {
    final provider = Provider.of<GraphDataProvider>(context, listen: false);
    serialDataSubscription?.cancel();
    _cancelSerialStaleWatchdog();
    _resetSerialIngestPipeline();
    lastDateTimeSerialDataArrival = DateTime.now();
    _ensureSerialStaleWatchdog(provider);
    serialDataSubscription = _serialUtil.dataStream?.listen((event) async {
      if (isOpeningFile) {
        _refreshSerialDataArrivalWhileOpeningFile();
        return;
      }
      lastDateTimeSerialDataArrival = DateTime.now();
      context.read<DataStatusProvider>().setMicrophoneDataStatus(false);
      arr = [processingUtil.thresholdingArraylength];
      serialSubscriptionListener(event, false, _availablePorts);
    }, onError: (error) {
      // if (error is SerialPortError) {
      _cancelSerialStaleWatchdog();
      forceSerialDisconnect = true;
      _serialUtil.closePort();
      Future.delayed(Duration(milliseconds: 1500), () {
        print(
            "SERIAL PORT ERROR -- DISCONNECTED: $error CALLSERIAL DATA SUBSCRIPTION");
        forceSerialDisconnect = false;
        _isSerialWebButtonEnabled = false;
        isDeviceConnect = false;
        isDeviceSelected = false;
        if (boardTimer != null) {
          boardTimer?.cancel();
          boardTimer = null;
        }
        if (deviceTimer != null) {
          deviceTimer?.cancel();
          deviceTimer = null;
        }

        _isDataIdentified = false;
        streamScrubBuilderController.add(Random().nextInt(100000));
        listenToMicrophone(1, provider);
      });
      // }
    });
    portName = _availablePorts.first;
  }

  /// Heart & Brain uses 222222 baud; FTDI 0x0403/0x6015 is opened at 500k for other boards.
  /// Bytes before the baud switch are line noise for this device — clear framing state and
  /// any partial 32-byte serial chunks so escape sequences match the BYB USB protocol
  /// (SpikerBox escape sequences in the Spike Recorder USB communication guide).
  void _resetSerialPipelineAfterBaudChange() {
    initMessageIdentifier();
    _residualBuffer.clear();
    _preEscapeSequenceBuffer.discardPendingInput();
    _preprocessingBuffer.discardPendingInput();
  }

  void serialWebButtonPressed(List<int> _baudRate) async {
    lastEstablishingConnectionTime = DateTime.now();
    try {
      await _serialUtil.closePort();
    } catch (err) {
      print("ERROR IN SERIAL WEB BUTTON PRESSED: $err");
    }

    try {
      // int baudRate = context.read<ConstantProvider>().getBaudRate();
      int baudRate = 0;
      print("getAvailablePorts serialWebButtonPressed: $baudRate");
      List<String> availablePorts = [];
      try {
        availablePorts = await _serialUtil.getAvailablePortsWeb(
            baudRate, serialErrorCallback);
      } catch (err) {
        print("ERROR GETTING AVAILABLE PORTS: $err");
        isSerialDeviceFound = false;
        if (err.toString().contains("BYPASS")) {
          _isSerialWebButtonEnabled = false;
          setState(() {});
          return;
        }
        PanaraInfoDialog.show(
          context,
          textColor: Colors.red,
          title: "Error",
          message: err.toString(),
          buttonText: "Okay",
          onTapDismiss: () {
            Navigator.pop(context);
            _isSerialWebButtonEnabled = false;
            setState(() {});
          },
          panaraDialogType: PanaraDialogType.error,
          barrierDismissible: false,
        );

        return;
      }

      if (availablePorts.isEmpty) {
        _isSerialWebButtonEnabled = false;
        return;
      }
      print("availablePorts GRAPH TEMPLATE: $availablePorts");

      // Provider.of<GraphResumePlayProvider>(context, listen: false)
      //     .setGraphResumePlay(false);
      GraphTemplate.isLoadingFile = 0;
      isOpeningFile = false;
      bool isPlay = true;
      Provider.of<GraphResumePlayProvider>(context, listen: false)
          .setGraphResumePlay(isPlay);
      _toPauseGraph = isPlay;
      GraphTemplate.isPlayerPaused = !isPlay;
      _pendingPlayback = false;

      serialDataSubscription?.cancel();
      _availablePorts = List<String>.from(availablePorts);
      if (_availablePorts.isEmpty) {
        _isSerialWebButtonEnabled = false;
        return;
      }
      if (!mounted) return;
      // run audio until serial data is identified
      // Provider.of<PortScanProvider>(context, listen: false)
      //     .setPortScanList(_availablePorts);
      // context.read<DataStatusProvider>().setMicrophoneDataStatus(false);

      if (!mounted) return;
      bool dummyDataStatus = context.read<DataStatusProvider>().isSampleDataOn;
      bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
      final provider = Provider.of<GraphDataProvider>(context, listen: false);
      print(
          "_serialUtil.dataStream $isAudioListen $dummyDataStatus | $_isDataIdentified $isDeviceSelected");
      isDeviceConnect = true;
      isDeviceSelected = false;
      isSerialDeviceFound = false;
      _isDataIdentified = false;
      foundDevices = "";
      _isBoardTimerRunning = false;
      _isDeviceTimerRunning = false;
      boardTimer?.cancel();
      boardTimer = null;
      deviceTimer?.cancel();
      deviceTimer = null;
      _resetSerialPipelineAfterBaudChange();
      streamScrubBuilderController.add(Random().nextInt(100000));
      callSerialDataSubscription();
      // Do not wait for the first ADC chunk (2s delayed path in [serialSubscriptionListener]).
      Future<void>.delayed(const Duration(milliseconds: 150), () {
        if (!mounted || _availablePorts.isEmpty || isDeviceSelected) {
          return;
        }
        _serialUtil.writeToPort(
          bytesMessage: UsbCommand.hwTypeInquiry.cmdAsBytes(),
          address: _availablePorts.last,
        );
      });
    } catch (e) {
      Debugging.printing("Opening port failed:\n$e");
    }
    setState(() {});
  }

  onTriggerDisconnect(String p1) {
    isSerialDeviceFound = false;
    // if (p1 == "") {
    //   return;
    // }

    final provider = Provider.of<GraphDataProvider>(context, listen: false);

    _cancelSerialStaleWatchdog();
    forceSerialDisconnect = true;
    print("SERIAL PORT ERROR -- DISCONNECTED");
    _serialUtil.closePort();
    Future.delayed(Duration(milliseconds: 2500), () {
      forceSerialDisconnect = false;
      _isSerialWebButtonEnabled = false;
      isDeviceConnect = false;
      isDeviceSelected = false;
      if (boardTimer != null) {
        boardTimer?.cancel();
        boardTimer = null;
      }
      _isDataIdentified = false;
      streamScrubBuilderController.add(Random().nextInt(100000));
      listenToMicrophone(1, provider);
    });
  }

  getTabbedViewChildren(int idx) {
    print(
        "customSliderBarArray.length -1 >= idx : ${customSliderBarArray.length} >= $idx");
    double? maxBoxWidth = kIsWeb
        ? 600
        : Platform.isIOS || Platform.isAndroid
            ? 500
            : 600;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header Row
          // 2. Main Content Container
          // Replaced Expanded with Center + ConstrainedBox
          Center(
            // child: ConstrainedBox(
            //   constraints: BoxConstraints(
            //     maxWidth: maxBoxWidth,
            //   ),
            child: Column(
              mainAxisSize: MainAxisSize.max, // Vital for scrolling
              children: [
                SizedBox(height: 0),
                _predefinedFilterSettings(idx),
                // _mutingSpeakers(),
                // if (customSliderBarArray.length -1 >= idx) ... [
                if (serialUsageType == "Custom") ...[
                  // Text("ABCDEFGHIJ --- $idx"),
                  Container(
                    color: Color(0xFF2e2e2e),
                    padding: EdgeInsets.fromLTRB(10, 0, 10, 0),
                    child: Divider(
                      thickness: 1,
                      color: Color(0x28707070),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Color(0xFF2e2e2e),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                    ),
                    // width: maxBoxWidth,
                    child: customSliderBarArray[idx],
                  ),

                  // CustomSliderBarButton(
                  //   readOnly: true,
                  //   sliderValue: customSliderBarArray[idx].sliderValue, startValue: customSliderBarArray[idx].startValue, endValue: customSliderBarArray[idx].endValue, processingUtil: processingUtil,
                  //   onHighPassFilterSetup: (FilterSetup filterSetup) {}, onLowPassFilterSetup: (FilterSetup filterSetup) {}, onSampleChange: (bool isSampleDataOn) {},
                  //   isMicrophoneEnable: (bool isMicrophoneEnable) {
                  //     context
                  //         .read<DataStatusProvider>()
                  //         .setMicrophoneDataStatus(
                  //             isMicrophoneEnable);
                  //   },
                  //   channelIdx: customSliderBarArray[idx].channelIdx, channelCount: customSliderBarArray[idx].channelCount)
                ] else
                  ...[],
              ],
            ),
            // ),
          ),
        ],
      ),
    );
  }

  void createTabBarConfiguration(channelCount, provider) {
    print("CreateTabBarConfiguration : $channelCount");
    channelTabTheme =
        TabbedViewThemeData.classic(borderColor: Color(0xFF222222));
    // channelTabTheme?.tab.closeIcon = IconProvider.data(IconData(0x0000, fontFamily: "IcomoonIcons"));
    // channelTabTheme?.tab.hoverButtonColor = Colors.transparent;
    channelTabTheme?.contentArea.decoration =
        BoxDecoration(color: Color(0xFF222222));

    // channelTabTheme?.tab.buttonPadding = EdgeInsets.zero;
    TabStatusThemeData selectedStatusTheme = TabStatusThemeData(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16), topRight: Radius.circular(16)),
          color: Color(0xFF2e2e2e)),
      fontColor: Colors.white,
      margin: EdgeInsets.only(left: 30, right: 10),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      paddingWithoutButton: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      innerBottomBorder: BorderSide.none,

      // path: _drawFolderTabPath,
      // color: Color(0xFF2D2D2D), // Dark grey from your image
    );
    TabStatusThemeData normalStatusTheme = TabStatusThemeData(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16), topRight: Radius.circular(16)),
          color: Color(0xFF181818)),
      fontColor: Colors.white,
      margin: EdgeInsets.only(left: 30, right: 10),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      paddingWithoutButton: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
    // channelTabs = [
    //   TabData(text: '   1   ', selectedStatusTheme: selectedStatusTheme, normalStatusTheme: normalStatusTheme, highlightedStatusTheme: normalStatusTheme, draggable: false, closable: false,
    //     content: ClipRRect(
    //       borderRadius: BorderRadius.all(Radius.circular(16)),
    //       clipBehavior: Clip.antiAlias,
    //       child: Container(
    //         color: Color(0xFF2e2e2e),
    //         child: Center(child: getTabbedViewChildren(0)),
    //       ),
    //     )
    //     // content: Container(color: Color(0xFF222222), child: Center(child: Text("123123123")))

    //   ),
    //   // TabData(text: '   2   ', selectedStatusTheme: selectedStatusTheme, normalStatusTheme: normalStatusTheme, highlightedStatusTheme: normalStatusTheme, draggable: false, closable: false,
    //   //   content: Container(color: Color(0xFF222222), child: Center(child: Text("123123123")))
    //   // ),
    // ];
    channelTabs.clear();
    for (int idx = 0; idx < channelCount; idx++) {
      channelTabs.add(TabData(
          text: '   ${idx + 1}   ',
          selectedStatusTheme: selectedStatusTheme,
          normalStatusTheme: normalStatusTheme,
          highlightedStatusTheme: normalStatusTheme,
          draggable: false,
          closable: false,
          content: ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            clipBehavior: Clip.antiAlias,
            // child: Container(color: Color(0xFF2e2e2e), child: Center(child: getTabbedViewChildren(idx))),
            child: Container(
                color: Color(0xFF2e2e2e),
                child: Center(child: getTabbedViewChildren(idx))),
          )));
    }
    _channelTabController = TabbedViewController(channelTabs);
  }

  Widget getIconFilterWidget(String serialType, bool isSelected) {
    Widget iconWidget = SizedBox();
    Color iconColor = Colors.transparent;
    if (serialType == "EMG") {
      iconColor = isSelected ? Color(0xFFffc600) : Color(0xFF585858);
      iconWidget = SvgPicture.asset('assets/icons/config_emg_off.svg',
          width: 60, height: 60);
    } else if (serialType.toUpperCase() == "ECG") {
      iconColor = isSelected ? Color(0xFFff805f) : Color(0xFF585858);
      iconWidget = SvgPicture.asset('assets/icons/config_ecg_off.svg',
          width: 60, height: 60);
    } else if (serialType.toUpperCase() == "Neuron") {
      iconColor = isSelected ? Color(0xFFd205a5) : Color(0xFF585858);
      iconWidget = SvgPicture.asset('assets/icons/config_neuron_off.svg',
          width: 60, height: 60);
    } else if (serialType.toUpperCase() == "EEG") {
      iconColor = isSelected ? Color(0xFF0093ff) : Color(0xFF585858);
      iconWidget = SvgPicture.asset('assets/icons/config_eeg_off.svg',
          width: 60, height: 60);
    } else if (serialType.toUpperCase() == "PLANT") {
      iconColor = isSelected ? Color(0xFF00aa50) : Color(0xFF585858);
      iconWidget = SvgPicture.asset('assets/icons/config_plant_off.svg',
          width: 60, height: 60);
    } else if (serialType.toUpperCase() == "CUSTOM") {
      iconColor = isSelected ? Color(0xFFDBDBDB) : Color(0xFF707070);
      iconWidget = SvgPicture.asset('assets/icons/config_plant_off.svg',
          width: 60, height: 60);
    }
    return Padding(
        padding: const EdgeInsets.all(15.0),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: iconColor,
                shape: BoxShape.circle,
                border: Border.all(color: iconColor, width: 30),
              ),
            ),
            Positioned(
              top: 0,
              right: 10,
              child: iconWidget,
            ),
          ],
        ));
  }

  // buildPredefinedFilter(int channelIdx, String serialType) {
  //   // bool isSelected = serialUsageType.contains(serialType);
  //   bool isSelected = true;
  //   print("serialType: $serialType -- $serialUsageType ||| isSelected: $isSelected");
  //   ButtonStyle style = ElevatedButton.styleFrom(
  //     // Toggle colors based on selection
  //     backgroundColor: isSelected ? Colors.blue : Colors.grey[300],
  //     foregroundColor: isSelected ? Colors.white : Colors.black,
  //   );

  //   return [
  //     getIconFilterWidget(serialType, isSelected),
  //     Column(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         Text(serialType, style: TextStyle(fontSize: 16, color: Colors.white)),
  //         Text("Heartbeats", style: TextStyle(fontSize: 12, color: Color(0xFF707070))),

  //       ],
  //     ),
  //     Spacer(),
  //     Padding(
  //       padding: const EdgeInsets.only(right:15.0),
  //       child: ElevatedButton(
  //         style: ElevatedButton.styleFrom(
  //           backgroundColor: SoftwareColors.kButtonBackGroundColor,
  //           shape: RoundedRectangleBorder(
  //             borderRadius: BorderRadius.circular(12),
  //           ),
  //         ),
  //         onPressed: () {
  //           isDetailConfiguration = !isDetailConfiguration;
  //           customizeDetailChannelIdx = channelIdx;
  //           configTitle = "Channel Settings";
  //           print("Start channelIdx: $channelIdx --- ${customSliderBarArray[channelIdx].startValue}");
  //           print("zzz customSliderBarArray : ${customSliderBarArray}");
  //           print("End channelIdx: $channelIdx --- ${customSliderBarArray[channelIdx].endValue}");
  //           Provider.of<CustomRangeSliderProvider>(context, listen: false)
  //             .setStartValue(customSliderBarArray[customizeDetailChannelIdx].startValue, customizeDetailChannelIdx);
  //           Provider.of<CustomRangeSliderProvider>(context, listen: false)
  //             .setEndValue(customSliderBarArray[customizeDetailChannelIdx].endValue, customizeDetailChannelIdx);

  //           setState(() {});

  //         },
  //         child: Text("SETUP CHANNEL", style: TextStyle(color: Colors.white)),
  //       ),
  //     ),

  //   ];
  // }

  buildPredefinedFilter(int channelIdx, String serialType) {
    List<String> predefinedFilters = predefinedFiltersChannel[channelIdx];
    print("predefinedFiltersChannel: $predefinedFilters");
    List<Widget> widgets = [];
    if (predefinedFilters.length >= 0) {
      // predefinedFilters = ["EMG", "ECG", "EEG", "Custom"];
      for (String filter in predefinedFilters) {
        widgets.add(buildSerialUsageTypeButton(filter, channelIdx));
      }
      return widgets;
    } else {
      return [SizedBox()];
    }
    // return Container(
    //   padding: EdgeInsets.fromLTRB(0, 10, 0, 0),
    //   decoration: BoxDecoration(
    //     color: Color(0x14D9D9D9),
    //     borderRadius: BorderRadius.circular(16),
    //   ),
    // );
  }

  /// Logs raw UART bytes/sec (debug). This includes protocol framing, device
  /// messages, and any non-sample bytes — not the same as
  /// `sampleRate × decoded bytes per sample`.
  void _recordSerialRxThroughput(int byteCount) {
    if (!_serialRxThroughputStopwatch.isRunning) {
      _serialRxThroughputStopwatch.start();
    }
    _serialRxBytesInWindow += byteCount;
    if (_serialRxThroughputStopwatch.elapsed < _serialRxThroughputLogInterval) {
      return;
    }
    final elapsedSec =
        _serialRxThroughputStopwatch.elapsedMilliseconds / 1000.0;
    final rate = elapsedSec > 0 ? _serialRxBytesInWindow / elapsedSec : 0.0;
    final avgUartBytesPerSample =
        rate / _serialRxBaselineSampleRate; // if ADC is really at this rate
    final decodedPayloadFloor =
        _serialRxBaselineSampleRate * _channelBytes; // int16-style frames only
    final impliedSpsIfWireMatchesChannelBytes =
        _channelBytes > 0 ? rate / _channelBytes : 0.0;
    if (kDebugMode) {
      debugPrint(
        'SERIAL RX: ${rate.toStringAsFixed(0)} B/s '
        '(${_serialRxBytesInWindow} B / ${elapsedSec.toStringAsFixed(2)} s) | '
        '@ ${_serialRxBaselineSampleRate} Hz → '
        '${avgUartBytesPerSample.toStringAsFixed(2)} UART B/sample (avg) | '
        'if every byte were sample data at $_channelBytes B/frame → '
        '${impliedSpsIfWireMatchesChannelBytes.toStringAsFixed(0)} frames/s '
        '(decoded floor ~$decodedPayloadFloor B/s; mic/UI $_sampleRate Hz)',
      );
    }
    _serialRxBytesInWindow = 0;
    _serialRxThroughputStopwatch.reset();
    _serialRxThroughputStopwatch.start();
  }

  void _cancelSerialStaleWatchdog() {
    _serialStaleWatchdogTimer?.cancel();
    _serialStaleWatchdogTimer = null;
  }

  /// While a file is loading/playing, live serial RX may pause — do not treat as disconnect.
  void _refreshSerialDataArrivalWhileOpeningFile() {
    lastDateTimeSerialDataArrival = DateTime.now();
  }

  void _ensureSerialStaleWatchdog(GraphDataProvider provider) {
    if (_serialStaleWatchdogTimer != null) return;
    _serialStaleWatchdogTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || isRecording == 1 || isOpeningFile) return;
      final lastArrival = lastDateTimeSerialDataArrival;
      if (lastArrival == null) return;
      if (DateTime.now().difference(lastArrival).inSeconds >
          _serialDataStaleTimeoutSeconds) {
        _recoverFromSerialDataTimeout(provider);
      }
    });
  }

  void _recoverFromSerialDataTimeout(GraphDataProvider provider) {
    _cancelSerialStaleWatchdog();
    boardTimer?.cancel();
    boardTimer = null;
    deviceTimer?.cancel();
    deviceTimer = null;
    _isBoardTimerRunning = false;
    _isDeviceTimerRunning = false;
    serialDataSubscription?.cancel();
    serialDataSubscription = null;
    _rxSub?.cancel();
    _rxSub = null;
    isDeviceConnect = true;
    isDeviceSelected = false;
    isSerialDeviceFound = false;
    _isDataIdentified = false;
    GraphTemplate.isLoadingFile = 0;
    foundDevices = "";
    _resetSerialIngestPipeline();
    try {
      _serialUtil.closePort();
    } catch (err) {
      print("ERROR CLOSING PORT ON SERIAL STALE: $err");
    }
    print(
        "SERIAL DATA STALE (>${_serialDataStaleTimeoutSeconds}s), falling back to microphone");
    listenToMicrophone(1, provider);
  }

  void serialSubscriptionListener(
      Uint8List event, bool isMfi, listOfPort) async {
    // _recordSerialRxThroughput(event.length);

    if (isOpeningFile) {
      _refreshSerialDataArrivalWhileOpeningFile();
      return;
    }
    lastDateTimeSerialDataArrival = DateTime.now();
    final provider = Provider.of<GraphDataProvider>(context, listen: false);
    _ensureSerialStaleWatchdog(provider);

    bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
    // print("IS AUDIO LISTEN | Writing to port b:; : ${isAudioListen} --- bytes : ${event.length}");
    // if (!isAudioListen) {
    if (true) {
      int drawSurfaceWidth = MediaQuery.of(context).size.width.toInt();
      if (isDeviceConnect) {
        if (isRecording == 1) return;
        isDeviceConnect = false;

        print(
            "Writing to port b:; : ${UsbCommand.hwTypeInquiry.cmdAsBytes()} ${DateTime.now().millisecondsSinceEpoch}");
        Future.delayed(const Duration(milliseconds: 400), () {
          if (isDeviceSelected) {
            return;
          }
          print("SEND BYTES DELAYED: ${DateTime.now().millisecondsSinceEpoch}");
          if (isMfi) {
            BybAccessory.sendBytes(UsbCommand.hwTypeInquiry.cmdAsBytes());
          } else if (listOfPort.isNotEmpty) {
            _serialUtil.writeToPort(
                bytesMessage: UsbCommand.hwTypeInquiry.cmdAsBytes(),
                address: listOfPort.last);
          }
        });
      }
      if (_isDataIdentified) {
        if (!isAudioListen && event.isNotEmpty && _shouldRunLiveMonitor()) {
          _registerWebLivePlaybackListener();
          unawaited(_ensureLiveMonitorPlayer());
        }
        serialNativeDataSubscription(event, isAudioListen);
      } else {
        if (!isDeviceConnect && !isDeviceSelected) {
          // print("_preEscapeSequenceBuffer ADDBYTES EVENT: ${event} | isDeviceConnect: ${isDeviceConnect} | isDeviceSelected: ${isDeviceSelected}");
          // if (event.contains(255)) {
          //   // print("_preEscapeSequenceBuffer ADDBYTES EVENT: ${event}");
          // }
          _preEscapeSequenceBuffer.addBytes(event);
        }
        if (isDeviceSelected) {
          // !isDeviceConnect &&
          _isDataIdentified = true;
          if (!_isBoardTimerRunning) {
            _isBoardTimerRunning = true;
            if (boardTimer != null) {
              boardTimer?.cancel();
              boardTimer = null;
            }
            boardTimer = Timer.periodic(Duration(seconds: 3), (timer) {
              if (isRecording == 1) return;
              if (GraphTemplate.selectedBoard != null &&
                  GraphTemplate.selectedBoard!.expansionBoards != null &&
                  GraphTemplate.selectedBoard!.expansionBoards!.isEmpty) return;

              _isBoardTimerRunning = false;
              print("Writing to port board:;");
              Uint8List commandBytes =
                  Uint8List.fromList(utf8.encode("board:;"));
              if (isMfi) {
                BybAccessory.sendBytes(UsbCommand.hwTypeInquiry.cmdAsBytes());
              } else {
                if (_availablePorts.isNotEmpty) {
                  _serialUtil.writeToPort(
                      bytesMessage: commandBytes,
                      address: _availablePorts.last);
                }
              }
            });
          }
          if (!GraphTemplate.isPlayerPaused) {
            if (!isAudioListen && event.isNotEmpty && _shouldRunLiveMonitor()) {
              _registerWebLivePlaybackListener();
              unawaited(_ensureLiveMonitorPlayer());
            }
            _enqueueSerialIngest(
              event,
              provider,
              drawSurfaceWidth,
              paintFromZero: true,
            );
          } else {
            // await processingUtil.processDisplaySerialData(displayTimeMs.toInt(), deviceType, drawSurfaceWidth, provider);
            // int fromSample = (-bufferPaddingLeft).toInt();
            // int toSample = (fromSample + displayTimeMs * 0.001 * _sampleRate).toInt();
            int maxSamples =
                (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
            int toSample = (maxSamples + bufferPaddingLeft).toInt();
            toSample = min(maxSamples, toSample);
            int fromSample =
                (toSample - displayTimeMs * 0.001 * _sampleRate).toInt();
            DraggableGraph.startPositionIdx = fromSample;
            DraggableGraph.endPositionIdx = toSample;
            // DEBUG STEVE
            // return;

            // processingUtil.prepareDisplayMicrophoneData([Int16List(0)], drawSurfaceWidth, channelCount, displayTimeMs, provider, fromSample, toSample );
            await processingUtil.processDisplaySerialData(displayTimeMs.toInt(),
                deviceType, drawSurfaceWidth, provider, fromSample, toSample);

            provider.inputListener(Uint8List(0));
          }
        } else {
          if (!_isDeviceTimerRunning && event.isNotEmpty) {
            _isDeviceTimerRunning = true;
            if (deviceTimer != null) {
              deviceTimer?.cancel();
              deviceTimer = null;
            }
            deviceTimer = Timer.periodic(Duration(seconds: 4), (timer) {
              if (isRecording == 1) return;
              print("Writing to port device:;");
              if (isMfi) {
                BybAccessory.sendBytes(UsbCommand.hwTypeInquiry.cmdAsBytes());
              } else {
                _serialUtil.writeToPort(
                    bytesMessage: UsbCommand.hwTypeInquiry.cmdAsBytes(),
                    address: listOfPort.last);
              }
              // _serialUtil.writeToPort(bytesMessage: UsbCommand.hwTypeInquiry.cmdAsBytes(), address: _availablePorts.last);
            });
          }
        }
      }
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
  bool _checked50 = false;
  bool _checked60 = false;
  late FilterSetup _notchPassFilterSettings;

  @override
  void initState() {
    super.initState();

    _notchPassFilterSettings = FilterSetup(
        filterConfiguration: FilterConfiguration(
            cutOffFrequency: 50, sampleRate: widget.sampleRateParam.toInt()),
        filterType: FilterType.notchFilter,
        channelCount: channelCountBuffer,
        isFilterOn: false);
  }

  void _apply50Hz(bool checked, int sampleRate) {
    setState(() {
      _checked50 = checked;
      if (checked) {
        _checked60 = false;
      }
    });
    final dataStatus = context.read<DataStatusProvider>();
    if (checked) {
      dataStatus.set60HertzStatus(false);
    }
    dataStatus.set50HertzStatus(checked);
    _notchPassFilterSettings = _notchPassFilterSettings.copyWith(
      filterType: FilterType.notchFilter,
      isFilterOn: checked,
      filterConfiguration: FilterConfiguration(
        cutOffFrequency: 50,
        sampleRate: sampleRate,
      ),
    );
    widget.onTapNotchFrequency(_notchPassFilterSettings);
  }

  void _apply60Hz(bool checked, int sampleRate) {
    setState(() {
      _checked60 = checked;
      if (checked) {
        _checked50 = false;
      }
    });
    final dataStatus = context.read<DataStatusProvider>();
    if (checked) {
      dataStatus.set50HertzStatus(false);
    }
    dataStatus.set60HertzStatus(checked);
    _notchPassFilterSettings = _notchPassFilterSettings.copyWith(
      filterType: FilterType.notchFilter,
      isFilterOn: checked,
      filterConfiguration: FilterConfiguration(
        cutOffFrequency: 60,
        sampleRate: sampleRate,
      ),
    );
    widget.onTapNotchFrequency(_notchPassFilterSettings);
  }

  @override
  Widget build(BuildContext context) {
    final sampleRate = context.watch<SampleRateProvider>().sampleRate;
    return Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 0, 10),
          child: const Icon(
            IconData(0xe90b, fontFamily: "IcomoonIcons"),
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          "Attenuate frequency (Notch filter) : ",
          style: SoftwareTextStyle().kWtMediumTextStyle,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
            child: Row(
              children: [
                Text(
                  "50 Hz",
                  style: SoftwareTextStyle().kWtMediumTextStyle,
                ),
                WhiteColorCheckBox(
                  value: _checked50,
                  onChanged: (checked) => _apply50Hz(checked, sampleRate),
                ),
                const SizedBox(width: 16),
                Text(
                  "60 Hz",
                  style: SoftwareTextStyle().kWtMediumTextStyle,
                ),
                WhiteColorCheckBox(
                  value: _checked60,
                  onChanged: (checked) => _apply60Hz(checked, sampleRate),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Custom checkbox with explicit green fill — Material [Checkbox] theming is
/// unreliable on Windows desktop (checked state often stays unstyled).
class WhiteColorCheckBox extends StatelessWidget {
  const WhiteColorCheckBox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  static const double _size = 20;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            color: value ? SoftwareColors.kGraphColor : Colors.transparent,
            border: Border.all(color: Colors.white, width: 1.5),
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: value
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : null,
        ),
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
      {required this.child1,
      required this.child3,
      required this.child2,
      required this.child4,
      required this.childOverlay,
      required this.notifier,
      required this.recordingNotifier});

  final Widget child1;
  final Widget child2;
  final Widget child3;
  final Widget child4;
  final Widget childOverlay;
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
    return Consumer<SoftwareConfigProvider>(
        builder: (context, softwareSetting, snapshot) {
      return SizedBox.expand(
        child: Stack(
          children: [
            widget.child1,

            Positioned(
              left: 0,
              bottom: 100,
              child: ValueListenableBuilder<List<int>>(
                  valueListenable: widget.recordingNotifier,
                  builder: (context, snapshot, _) {
                    if (snapshot.isNotEmpty && snapshot[0] != 0) {
                      // if is recording
                      // return Container();
                      Duration difference =
                          DateTime.fromMillisecondsSinceEpoch(snapshot[1])
                              .difference(DateTime.fromMillisecondsSinceEpoch(
                                  snapshot[0])); // Duration: 2:30:45.864000
                      String strTimeDiff = formatDuration(difference);

                      return SizedBox(
                          // color: Colors.red,
                          width: MediaQuery.of(context).size.width,
                          height: 30,
                          child: Center(
                            child: Container(
                              decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(16)),
                              padding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(8)),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    strTimeDiff,
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ));
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
            if (GraphTemplate.isLoadingFile > 0) ...{
              getTimeScrubWidget(),
            },
            // if (!GraphTemplate.isPlayerPaused)... {
            if (GraphTemplate.isLoadingFile >= 1) ...{
              // strMinTime = "00:00 000";
              Positioned(
                left: 50,
                bottom: 70,
                child: Container(
                  margin: kIsWeb
                      ? const EdgeInsets.fromLTRB(0, 0, 0, 0)
                      : Platform.isAndroid || Platform.isIOS
                          ? const EdgeInsets.fromLTRB(0, 0, 0, 40)
                          : const EdgeInsets.fromLTRB(0, 0, 0, 0),
                  child: Text(strMinTime,
                      textAlign: TextAlign.left,
                      style: TextStyle(color: Colors.white)),
                ),
              ),
              Positioned(
                right: 50,
                bottom: 70,
                child: Container(
                    margin: kIsWeb
                        ? const EdgeInsets.fromLTRB(0, 0, 0, 0)
                        : Platform.isAndroid || Platform.isIOS
                            ? const EdgeInsets.fromLTRB(0, 0, 0, 40)
                            : const EdgeInsets.fromLTRB(0, 0, 0, 0),
                    width: 150,
                    child: Text(strMaxTime,
                        textAlign: TextAlign.right,
                        style: TextStyle(color: Colors.white))),
              )
            },

            // },
            softwareSetting.isSettingEnable
                ? Positioned.fill(
                    child: Container(
                      color: Colors.black54.withOpacity(0.9),
                      // color: Colors.red,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 15),
                        child: widget.child3,
                      ),
                    ),
                  )
                : Container(),
            widget.childOverlay,
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
    String milliseconds =
        absDuration.inMilliseconds.remainder(1000).toString().padLeft(3, "0");

    // Add a negative sign if the original duration was negative
    String negativeSign = duration.isNegative ? '-' : '';

    return '$negativeSign$hours:$minutes:$seconds $milliseconds';
  }

  getTimeScrubWidget() {
    horizontalDragXFix = MediaQuery.of(context).size.width - 100 - 20;
    strMinTime = getStrMinTime(horizontalDragX, horizontalDragXFix, maxTime);
    strMaxTime = getStrMinTime(horizontalDragXFix, horizontalDragXFix, maxTime);

    return Positioned(
      left: 0,
      bottom: 100,
      child: Container(
        margin: kIsWeb
            ? const EdgeInsets.fromLTRB(0, 0, 0, 0)
            : Platform.isAndroid || Platform.isIOS
                ? const EdgeInsets.fromLTRB(0, 0, 0, 40)
                : const EdgeInsets.fromLTRB(0, 0, 0, 0),
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
    return Column(
      children: [
        Expanded(
          flex: 6,
          child: Container(
            color: Color(0xFF222222),
            child: SoundWaveView(),
          ),
        ),
      ],
    );
  }
}

class _PortsArea extends StatelessWidget {
  const _PortsArea({
    required this.deviceName,
    required this.availablePorts,
    required this.onReceive,
    required this.onWrite,
    required this.onTriggerDisconnect,
  });

  final ValueNotifier<String?> deviceName;
  final List<String> availablePorts;
  final Function(String) onReceive;
  final Function(String) onWrite;
  final Function(String) onTriggerDisconnect;

  @override
  Widget build(BuildContext context) {
    print("PORTS AREA");
    // deviceName.value = Random().nextInt(1000000).toString();
    return Container(
      // margin: const EdgeInsets.fromLTRB(0, 10, 0, 0),
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
      // decoration: BoxDecoration(
      //   color: Color(0xFF2e2e2e),
      //   borderRadius: BorderRadius.circular(16),
      // ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 0, 0),
                child: SvgPicture.asset(
                  'assets/icons/config_board.svg',
                  width: 20,
                  height: 20,
                ),
                // child: Icon(
                //   const IconData(0xe90e, fontFamily: "IcomoonIcons"),
                //   color: Colors.white,
                // ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                child: Text(
                  "Connected device",
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
              Expanded(
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
                  // child: Text("address", style: SoftwareTextStyle().kWtMediumTextStyle),
                  child: DarkDropdown(
                      kIsWeb: kIsWeb,
                      availablePorts: availablePorts,
                      onPortSelected: onPortSelected,
                      valueListenable: deviceName),
                ),
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

              kIsWeb
                  ? Container()
                  : Container(
                      width: 10,
                    ),
              //   padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              //   child: ElevatedButton(
              //     style: ElevatedButton.styleFrom(
              //       backgroundColor:
              //           SoftwareColors.kButtonBackGroundColor,
              //       shape: RoundedRectangleBorder(
              //         borderRadius: BorderRadius.circular(12),
              //       ),
              //     ),
              //     child: Text(
              //       "DISCONNECT",
              //       style: TextStyle(color: Colors.white),
              //     ),
              //     onPressed: () {
              //       onTriggerDisconnect(deviceName.value ?? "");
              //     },
              //   ),
              // ),
            ],
          ),
          // ValueListenableBuilder<String?>(
          //   valueListenable: deviceName,
          //   builder: (context, snapshot, _) {
          //     return snapshot != null
          //         ? Card(
          //             child: Padding(
          //               padding: const EdgeInsets.all(8.0),
          //               child: Text(snapshot),
          //             ),
          //           )
          //         : const SizedBox.shrink();
          //   },
          // ),
        ],
      ),
    );
  }

  onPortSelected(String p1) {
    print("onPortSelected: $p1");
    print("DISCONNECT USB");
    onWrite(p1);
    // forceSerialDisconnect =
    //     !forceSerialDisconnect;
    // _serialUtil.closePort();
    // Future.delayed(
    //     Duration(
    //         milliseconds:
    //             1500), () {
    //   if (context.mounted) {
    //     _availablePorts
    //         .clear();
    //     context
    //         .read<
    //             DataStatusProvider>()
    //         .setMicrophoneDataStatus(
    //             _availablePorts
    //                 .isEmpty);
    //     final provider = Provider
    //         .of<GraphDataProvider>(
    //             context,
    //             listen:
    //                 false);
    //     listenToMicrophone(
    //         1, provider);
    //   }
    //   // final provider = Provider.of<GraphDataProvider>(context, listen: false);
    // });
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
              // WhiteColorCheckBox(
              //   valueStatus: dataStatus.isMicrophoneData,
              //   onChanged: (value) {
              //     setState(() {
              //       _isMicrophoneEnable = value ?? false;
              //       if (_isMicrophoneEnable && _isSampleDataOn) {
              //         _isSampleDataOn = false;
              //         widget.onSampleChange(_isSampleDataOn);
              //       }
              //     });
              //     widget.isMicrophoneEnable(_isMicrophoneEnable);
              //   },
              // ),
              // Text(
              //   "Microphone On",
              //   style: SoftwareTextStyle().kWtMediumTextStyle,
              // )
            ],
          ),
        ],
      );
    });
  }
}

// https://dandiarchive.org/dandiset/000955/draft/files?location=sub-BH549&page=1
