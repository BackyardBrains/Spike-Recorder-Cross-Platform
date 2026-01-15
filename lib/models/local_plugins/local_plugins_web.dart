import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:native_add/model/model.dart';
import 'package:spikerbox_architecture/models/models.dart';
import 'package:spikerbox_architecture/models/local_plugins/local_plugins_check.dart';
import 'package:spikerbox_architecture/models/processing_utils/processing_util.dart';
import 'dart:js' as js;

import 'package:spikerbox_architecture/provider/graph_stream_data.dart';
import 'package:spikerbox_architecture/screen/graph_template.dart';
import 'package:spikerbox_architecture/widget/fft_painter.dart';

LocalPlugin getLocalPlugins() => LocalPluginWeb();

class LocalPluginWeb implements LocalPlugin {
  FilterSetup? _highPassFilterSetup;
  FilterSetup? _lowPassFilterSetup;
  int defaultChannelCountNoExpansionBoard = -1;
  int defaultSampleRateNoExpansionBoard = -1;
  @override
  String currentExpansionBoardString = "";


  static final List<Int16List?> _dataBuffer =
      List.generate(channelCountBuffer, (index) => null);

  final List<BufferHandlerOnDemand?> _bufferHandlerOnDemand =
      List.generate(channelCountBuffer, (index) => null);

  /// Starts web worker
  ///
  /// Sets up buffer also
  @override
  Future<void> spawnHelperIsolate() async {
    print("SPAWN HELPER ISOLATE WEB");
    postFilterStream = postFilterStreamController.stream.asBroadcastStream();
    postDisplayStream = postDisplayStreamController.stream.asBroadcastStream();
    postChannelCountStream = postChannelCountController.stream.asBroadcastStream();
    for (int i = 0; i < channelCountBuffer; i++) {
      _bufferHandlerOnDemand[i] = BufferHandlerOnDemand(
        chunkReadSize: 4000,
        onDataAvailable: (Uint8List newList) {
          onPacketAvailable(newList, i);
        },
      );
    }
    // js.context['sendSerialDataWeb'] = sendSerialData;
    js.context['onDataBufferAllocated'] = onDataBufferAllocated;
    js.context['onProcessingDone'] = onProcessingDone;
    js.context['onPostDisplay'] = onPostDisplay;
    js.context['onCallbackProcessFft'] = onCallbackProcessFft;
    js.context['onCallbackPrepareFftDrawing'] = onCallbackPrepareFftDrawing;
    js.context['setExpansionBoardTypeDart'] = setExpansionBoardTypeDart;
    js.context['setDefaultDeviceParameters'] = setDefaultDeviceParameters;
    js.context.callMethod("initializeModule", []);
  }

  @override
  Future<void> filterArrayElements(
      {required array,
      required int arrayLength,
      required int channelIdx}) async {
    // Int16List iList = Int16List.fromList(array);

    // Add data to circular buffer
    // _bufferHandlerOnDemand[channelIdx]?.addBytes(iList.buffer.asUint8List());
    _bufferHandlerOnDemand[channelIdx]?.addBytes(array);
    return;
  }

  @override
  Future<bool> initHighPassFilters(FilterSetup filterBaseSettingsModel) async {
    // _highPassFilterSetup = filterBaseSettingsModel;
    // js.context.callMethod("setBandFilterWeb", [
    //   filterBaseSettingsModel.
    //   filterBaseSettingsModel.filterConfiguration.sampleRate,
    //   filterBaseSettingsModel.filterConfiguration.cutOffFrequency,
    //   0.5
    // ]);
    return true;
  }

  @override
  Future<bool> initLowPassFilters(FilterSetup filterBaseSettingsModel) async {
    // _lowPassFilterSetup = filterBaseSettingsModel;
    // js.context.callMethod("sendToWebInitLowPassFilter", [
    //   filterBaseSettingsModel.channelCount,
    //   filterBaseSettingsModel.filterConfiguration.sampleRate,
    //   filterBaseSettingsModel.filterConfiguration.cutOffFrequency,
    //   0.5
    // ]);
    return true;
  }

  Future<bool> initNotchPassFilters(FilterSetup filterBaseSettingsModel) async {
    return false;
  }

  @override
  Stream<Uint8List>? postFilterStream;

  @override
  StreamController<Uint8List> postFilterStreamController =
      StreamController<Uint8List>();
  @override
  StreamController<int> postChannelCountController =
      StreamController<int>();

  /// When another packet is available for processing from buffer
  void onPacketAvailable(Uint8List packet, int channelIndex) {
    _bufferHandlerOnDemand[channelIndex]?.toFetchBytes = false;
    Int16List listFromBuffer = packet.buffer.asInt16List();
    if (_dataBuffer.isEmpty) {
      _bufferHandlerOnDemand[channelIndex]?.toFetchBytes = true;
      _bufferHandlerOnDemand[channelIndex]?.requestData();
      return;
    }

    // for (int i = 0; i < listFromBuffer.length; i++) {
    //   _dataBuffer[channelIndex]![i] = listFromBuffer[i];
    // }

    bool toApplyHighPass = false;
    bool toApplyLowPass = false;
    bool toApplyNotch = false;
    if (_highPassFilterSetup != null) {
      if (_highPassFilterSetup!.isFilterOn) {
        toApplyHighPass = true;
      }
    }
    if (_lowPassFilterSetup != null) {
      if (_lowPassFilterSetup!.isFilterOn) {
        toApplyLowPass = true;
      }
    }
    // js.context.callMethod("sendToWorkerApplyFilter", [
    //   channelIndex,
    //   listFromBuffer,
    //   toApplyHighPass,
    //   toApplyLowPass,
    //   toApplyNotch,
    // ]);
  }

  /// Called only once in the beginning to send address of buffer to dart
  void onDataBufferAllocated(Int16List dataBuffer, final channelIndex) {
    print("ON BUFFER ALLOCATED LOCAL PLUGIN - $channelIndex");
    _dataBuffer[channelIndex] = dataBuffer;
  }

  void setDefaultDeviceParameters(sampleRate, channelCount) {
    if (defaultChannelCountNoExpansionBoard == -1) {
      defaultSampleRateNoExpansionBoard = sampleRate;
      defaultChannelCountNoExpansionBoard = channelCount;
    }
  }

  /// Called from JS when processing completed on a packet
  void onProcessingDone(channelData, channelCounts) {
    // Int16List returnList = Int16List(_dataBuffer[channelIdx]?.length ?? 0);
    // for (int i = 0; i < returnList.length; i++) {
    //   returnList[i] = _dataBuffer[channelIdx]![i];
    // }
    // int len = channelData.length;
    // for (int i = 0; i < len; i++) {

    //   ProcessingUtil.drawingBuffers[i].setAll(0, channelData[0]);
    //   ProcessingUtil.drawingBufferCounts[i] = channelCounts[i];
    // }

    // postFilterStreamController.add(returnList.buffer.asUint8List());
    postFilterStreamController.add(Uint8List(0));

    // _bufferHandlerOnDemand[channelIdx]?.toFetchBytes = true;
    // _bufferHandlerOnDemand[channelIdx]?.requestData();
  }

  void setExpansionBoardTypeDart(expBoardType) {
    // print("setExpansionBoardTypeDart");
    // print(GraphTemplate.selectedBoard);
    // if (GraphTemplate.selectedBoard != null) {
    //   print("setExpansionBoardTypeDart1");
    //   if (GraphTemplate.selectedBoard!.expansionBoards != null) {
    //     print("setExpansionBoardTypeDart2 ${GraphTemplate.selectedBoard!.expansionBoards!}");
    //     for (var expBoard in GraphTemplate.selectedBoard!.expansionBoards!) {
    //       print("setExpansionBoardTypeDart3 ${expBoardType.toString()}");
    //       if (expBoard.boardType == expBoardType.toString()) {
    //         print("setExpansionBoardTypeDart4");
    //         if (currentExpansionBoardString == "" && expBoardType == 0) {
    //           return;
    //         } else
    //         if (currentExpansionBoardString != expBoardType.toString()) {
    //           currentExpansionBoardString = expBoardType.toString();
    //           // ProcessingBindings.instance.setSampleRate();
    //           if (expBoard.maxSampleRate != null) {
    //             print("setExpansionBoardTypeDart5");
    //             int boardChannels = -1;
    //             if (GraphTemplate.selectedBoard!.uniqueName == "HUMANSB") {
    //               if (expBoardType == 1) {
    //                 int expBoardSampleRate = int.parse(expBoard.maxSampleRate!);
    //                 boardChannels = int.parse(GraphTemplate.selectedBoard!.maxNumberOfChannels!);
    //                 print("SelectedBoard CHannel: ${GraphTemplate.selectedBoard!.maxNumberOfChannels!} --- maxNumberOfChannels: ${expBoard.maxNumberOfChannels!}");
    //                 postChannelCountController.add(boardChannels);
    //                 js.context.callMethod("initializeSerialWeb", [expBoardSampleRate, boardChannels, -1] );

    //               } else {
    //                 int expBoardSampleRate = int.parse(expBoard.maxSampleRate!);
    //                 boardChannels = int.parse(GraphTemplate.selectedBoard!.maxNumberOfChannels!) + int.parse(expBoard.maxNumberOfChannels!);
    //                 print("SelectedBoard CHannel: ${GraphTemplate.selectedBoard!.maxNumberOfChannels!} --- maxNumberOfChannels: ${expBoard.maxNumberOfChannels!}");
    //                 postChannelCountController.add(boardChannels);
    //                 js.context.callMethod("initializeSerialWeb", [expBoardSampleRate, boardChannels, -1] );

    //               }
    //             } else {

    //               int expBoardSampleRate = int.parse(expBoard.maxSampleRate!);
    //               boardChannels = int.parse(GraphTemplate.selectedBoard!.maxNumberOfChannels!) + int.parse(expBoard.maxNumberOfChannels!);
    //               print("SelectedBoard CHannel: ${GraphTemplate.selectedBoard!.maxNumberOfChannels!} --- maxNumberOfChannels: ${expBoard.maxNumberOfChannels!}");
    //               postChannelCountController.add(boardChannels);
    //               js.context.callMethod("initializeSerialWeb", [expBoardSampleRate, boardChannels, -1] );
    //             }


    //             if (expBoard.boardType == "4") {
    //               ProcessingUtil.medianChannelValueAdjuster = List.generate(boardChannels, (_) => 0);
    //               ProcessingUtil.medianChannelValueAdjuster[3] = -4096;
    //             }else {
    //               ProcessingUtil.medianChannelValueAdjuster = List.generate(boardChannels, (_) => 0);
    //             }
    //           }
    //         }
    //       } else 
    //       if (expBoardType == 0) {
    //         print("setExpansionBoardTypeDart3.5 : $currentExpansionBoardString");
    //         if (currentExpansionBoardString.isNotEmpty) {
    //           currentExpansionBoardString = "";
    //           postChannelCountController.add(defaultChannelCountNoExpansionBoard);
    //           js.context.callMethod("initializeSerialWeb", [defaultSampleRateNoExpansionBoard, defaultChannelCountNoExpansionBoard, -1] );
    //           defaultChannelCountNoExpansionBoard = -1;
    //           defaultSampleRateNoExpansionBoard = -1;              
    //         }
    //       }
    //     }
    //   }
    // }
  }

  void onPostDisplay(channelData, channelCounts) {
    postDisplayStreamController.sink.add(Uint8List(0));
  }




Int32List convertRgbaFloat32ListToInt32(Float32List fftColorList, Int32List outColorList) {
  // Ensure the input list has a multiple of 4 elements (R, G, B, A).
  if (fftColorList.length % 4 != 0) {
    // throw ArgumentError('The RGBA color list must have a length that is a multiple of 4.');
  }

  final int colorCount = fftColorList.length ~/ 4;

  for (int i = 0; i < colorCount; i++) {
    // Read the four float components (R, G, B, A)
    double R = fftColorList[i * 4];
    double G = fftColorList[i * 4 + 1];
    double B = fftColorList[i * 4 + 2];
    double A = fftColorList[i * 4 + 3];
    
    int r = (R * 255).round();
    int g = (G * 255).round();
    int b = (B * 255).round();
    int a = (A * 255).round();   
    outColorList[i] = (a << 24) | (r << 16) | (g << 8) | b;
  }

  return outColorList;
}    
  void onCallbackPrepareFftDrawing(resultFft, selectedChannelIdx) {
    // print("onCallbackPrepareFftDrawing");
    // print(resultFft);

    ProcessingUtil? processingUtil = GraphTemplate.processingUtil;
    processingUtil?.onCallbackPrepareFftDrawingWeb(resultFft, selectedChannelIdx);
  }

  void onCallbackProcessFft(out_window_count, out_window_size, out_fft_data, selectedChannel, channelCounts) {
    // print("onCallbackProcessFft out_fft_data: $selectedChannel $channelCounts");
    ProcessingUtil? processingUtil = GraphTemplate.processingUtil;
    // print("onCallbackProcessFft $out_window_count $out_window_size  ||| ${processingUtil?.window_count}" );
    int windowCount = ( (10.0 * 128) / (512 * 0.01).floor() ).floor();
    int windowSize = ( (32 * 4) ).floor();
    try {
      if (processingUtil != null && processingUtil.window_count.isEmpty) {

        processingUtil.window_count.clear();
        processingUtil.window_count.addAll([windowCount]);
        processingUtil.window_size.clear();
        processingUtil.window_size.addAll([windowSize]);
        if (processingUtil.out_fft.isEmpty) {
          processingUtil.out_fft.clear();
          processingUtil.out_fft = List<Float32List>.generate(windowCount, (idx)=> Float32List(windowSize));
        }
      } else {
        processingUtil?.window_count.setAll(0, out_window_count);
        processingUtil?.window_size.setAll(0, out_window_size);
      }
      
    }catch(err){
      print("err $err");
    }
    // print("onCallbackProcessFft1 ${processingUtil!.window_count[0]}");
    if (processingUtil!.window_count[selectedChannel] > 0) {
      int windowCounterFft = out_window_count[selectedChannel];
      int windowSizeFft = out_window_size[selectedChannel];
      // print("windowCounterFft $windowCounterFft ||| windowSizeFft $windowSizeFft ||| windowSize: $windowSize");
      // print("windowCounter $windowCounter ||| out_fft_data ${out_fft_data.length}");
      // print("processingUtil.fftBuffer : ${processingUtil.fftBuffer}");
      // return;

      for (int i = 0; i < windowCounterFft; i++) {
        // int outSize = out_window_count[0];
        Float32List out_fft_list = out_fft_data[i].sublist(0, windowSizeFft);
        // print("out_fft_list ${processingUtil.out_fft.length}");
        processingUtil.out_fft[i].setAll(0, out_fft_list);
        processingUtil.fftBuffer.put(processingUtil.out_fft, 0, windowCount);
      }
    }
  }



  Future<int> setBandFilter(double lowCutOffFreq, double highCutOffFreq) async {

    js.context.callMethod("setBandFilterWeb", [lowCutOffFreq, highCutOffFreq]);
    return 0;
  }

  Future<int> setNotchFilter(double centerFreq) async {
    js.context.callMethod("setNotchFilterWeb", [centerFreq]);
    // setNotchFilterWeb(centerFreq);
    return 0;
  }
  
  // List<Int16List> prepareDisplayMicrophoneData(List<Int16List> processedData, int drawSurfaceWidth, int channelCount, double displayTimeMs, GraphDataProvider provider) {
  //   js.context.callMethod("prepareDisplayMicrophoneData", [drawSurfaceWidth, channelCount, displayTimeMs]);
  //   return [];
  //   // prepareDisplayMicrophoneDataWeb(drawSurfaceWidth, channelCount, displayTimeMs);
  // }
  
  @override
  Stream<Uint8List>? postDisplayStream;
  
  @override
  StreamController<Uint8List> postDisplayStreamController =
      StreamController<Uint8List>();

  @override
  Stream<int>? postChannelCountStream;

}
