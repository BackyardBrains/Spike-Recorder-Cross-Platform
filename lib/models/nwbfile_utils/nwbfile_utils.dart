import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
// import 'dart:ffi';

// Conditional export based on platform
export "nwbfile_utils_native.dart"
    if (dart.library.html) "nwbfile_utils_web.dart";


// The abstract interface all implementations must follow
abstract class NWBFileUtil {
  Future<bool> processingInit(int sampleRate, int channelCount);
  Future<bool> addElectricalSeries(Int16List data, Int32List samplesCount, int selectedChannel,int channelCount, int isFinishRecording);
  Future<bool> readElectricalSeries(Int16List outSamples, Int32List outSamplesCount, int selectedChannel,int channelCount);
  Future<bool> seekElectricalSeries(Int16List outSamples, Int32List outSamplesCount, Int32List outConfig, int startTimeStamp, int endTimeStamp, int selectedChannel, int channelCount);
}

