
import 'dart:ffi';
import 'dart:io';

// FFI type definitions
typedef ProcessingInitNative = Int32 Function();
typedef ProcessingInit = int Function();

typedef ProcessingSetSampleRateNative = Int32 Function(Int32 sampleRate);
typedef ProcessingSetSampleRate = int Function(int sampleRate);

typedef ProcessingSetChannelCountNative = Int32 Function(Int32 channelCount);
typedef ProcessingSetChannelCount = int Function(int channelCount);

typedef ProcessingSetBitsPerSampleNative = Int32 Function(Int32 bitsPerSample);
typedef ProcessingSetBitsPerSample = int Function(int bitsPerSample);

typedef ProcessingSetSelectedChannelNative = Int32 Function(
    Int32 selectedChannel);
typedef ProcessingSetSelectedChannel = int Function(int selectedChannel);

typedef ProcessingSetBandFilterNative = Int32 Function(
    Float lowCutOffFreq, Float highCutOffFreq);
typedef ProcessingSetBandFilter = int Function(
    double lowCutOffFreq, double highCutOffFreq);

typedef ProcessingSetNotchFilterNative = Int32 Function(Float centerFreq);
typedef ProcessingSetNotchFilter = int Function(double centerFreq);
typedef ProcessingProcessMicrophoneStreamNative = Int32 Function(
    Pointer<Pointer<Int16>> outSamples, 
    Pointer<Int32> outSampleCounts,
    Pointer<Uint8> inData, 
    Int32 length);
typedef ProcessingProcessMicrophoneStream = int Function(
    Pointer<Pointer<Int16>> outSamples, 
    Pointer<Int32> outSampleCounts,
    Pointer<Uint8> inData, 
    int length);
typedef ProcessingProcessSampleStreamNative = Int32 Function(
    Pointer<Pointer<Int16>> outSamples, 
    Pointer<Int32> outSampleCounts,
    Pointer<Uint8> inData, 
    Int32 length,
    Int32 deviceType);
typedef ProcessingProcessSampleStream = int Function(
    Pointer<Pointer<Int16>> outSamples, 
    Pointer<Int32> outSampleCounts,
    Pointer<Uint8> inData, 
    int length,
    int deviceType);

typedef ProcessingFilterDataNative = Int32 Function(
    Pointer<Double> data, Int32 length);
typedef ProcessingFilterData = int Function(Pointer<Double> data, int length);

typedef ProcessingRmsNative = Float Function(Pointer<Int16> data, Int32 length);
typedef ProcessingRms = double Function(Pointer<Int16> data, int length);

typedef ProcessingMapNative = Int32 Function(
    Pointer<Float> outData,
    Pointer<Float> inData,
    Int32 length,
    Float inMin,
    Float inMax,
    Float outMin,
    Float outMax);
typedef ProcessingMap = int Function(
    Pointer<Float> outData,
    Pointer<Float> inData,
    int length,
    double inMin,
    double inMax,
    double outMin,
    double outMax);

typedef ProcessingProcessFftNative = Int32 Function(
    Pointer<Pointer<Float>> outFft,
    Pointer<Int32> outWindowCount,
    Pointer<Int32> outWindowSize,
    Pointer<Pointer<Int16>> inSamples,
    Pointer<Int32> inSampleCounts
);
typedef ProcessingProcessFft = int Function(
    Pointer<Pointer<Float>> outFft,
    Pointer<Int32> outWindowCount,
    Pointer<Int32> outWindowSize,
    Pointer<Pointer<Int16>> inSamples,
    Pointer<Int32> inSampleCounts
);

typedef ProcessingGetInformationNative = Int32 Function(
    Pointer<Int32> outInfo,
);
typedef ProcessingGetInformation = int Function(
    Pointer<Int32> outInfo,
);


typedef ProcessingResetFftNormalizationNative = Void Function();
typedef ProcessingResetFftNormalization = void Function();

typedef ProcessingIsAudioStreamAmModulatedNative = Int32 Function();
typedef ProcessingIsAudioStreamAmModulated = int Function();

typedef ProcessingGetAveragedSampleCountNative = Int32 Function();
typedef ProcessingGetAveragedSampleCount = int Function();

typedef ProcessingSetAveragedSampleCountNative = Void Function(Int32 count);
typedef ProcessingSetAveragedSampleCount = void Function(int count);

typedef ProcessingGetAveragingTriggerTypeNative = Int32 Function();
typedef ProcessingGetAveragingTriggerType = int Function();

typedef ProcessingSetAveragingTriggerTypeNative = Void Function(Int32 type);
typedef ProcessingSetAveragingTriggerType = void Function(int type);

typedef ProcessingSetThresholdNative = Void Function(Float threshold);
typedef ProcessingSetThreshold = void Function(double threshold);

typedef ProcessingResetThresholdNative = Void Function();
typedef ProcessingResetThreshold = void Function();

typedef ProcessingResumeThresholdNative = Void Function();
typedef ProcessingResumeThreshold = void Function();

typedef ProcessingPauseThresholdNative = Void Function();
typedef ProcessingPauseThreshold = void Function();

typedef ProcessingProcessThresholdNative = Int32 Function(
    Pointer<Pointer<Int16>> outSamples,
    Pointer<Int32> outSampleCounts,
    Pointer<Pointer<Int16>> inSamples,
    Pointer<Int32> inSampleCounts,
    Bool averageSamples);

typedef ProcessingProcessThreshold = int Function(
    Pointer<Pointer<Int16>> outSamples,
    Pointer<Int32> outSampleCounts,
    Pointer<Pointer<Int16>> inSamples,
    Pointer<Int32> inSampleCounts,
    bool averageSamples);

typedef ProcessingSetBpmProcessingNative = Void Function(Int32 processBpm);
typedef ProcessingSetBpmProcessing = void Function(int processBpm);

typedef ProcessingPrepareForSignalDrawingNative = Int32 Function(
    Pointer<Pointer<Int16>> outSamples,
    Pointer<Int32> outSampleCounts,
    Pointer<Float> outEventIndices,
    Pointer<Int32> outEventCount,
    Pointer<Int32> inEventIndices,
    Int32 inEventCount,
    Int32 fromSample,
    Int32 toSample,
    Int32 drawSurfaceWidth
);
typedef ProcessingPrepareForSignalDrawing = int Function(
    Pointer<Pointer<Int16>> outSamples,
    Pointer<Int32> outSampleCounts,
    Pointer<Float> outEventIndices,
    Pointer<Int32> outEventCount,
    Pointer<Int32> inEventIndices,
    int inEventCount,
    int fromSample,
    int toSample,
    int drawSurfaceWidth
);

typedef ProcessingCleanupNative = Void Function();
typedef ProcessingCleanup = void Function();

class ProcessingBindings {
  static DynamicLibrary? _lib;
  static ProcessingBindings? _instance;
  static bool _isDebugMode = true;

  late final ProcessingInit init;
  late final ProcessingSetSampleRate setSampleRate;
  late final ProcessingSetChannelCount setChannelCount;
  late final ProcessingSetBitsPerSample setBitsPerSample;
  late final ProcessingSetSelectedChannel setSelectedChannel;
  late final ProcessingSetBandFilter setBandFilter;
  late final ProcessingSetNotchFilter setNotchFilter;
  late final ProcessingProcessMicrophoneStream processMicrophoneStream;
  late final ProcessingProcessSampleStream processSampleStream;
  late final ProcessingFilterData filterData;
  late final ProcessingRms rms;
  late final ProcessingMap map;
  late final ProcessingProcessFft processFft;
  late final ProcessingResetFftNormalization resetFftNormalization;
  late final ProcessingIsAudioStreamAmModulated isAudioStreamAmModulated;
  late final ProcessingGetAveragedSampleCount getAveragedSampleCount;
  late final ProcessingSetAveragedSampleCount setAveragedSampleCount;
  late final ProcessingGetAveragingTriggerType getAveragingTriggerType;
  late final ProcessingSetAveragingTriggerType setAveragingTriggerType;
  late final ProcessingSetThreshold setThreshold;
  late final ProcessingResetThreshold resetThreshold;
  late final ProcessingResumeThreshold resumeThreshold;
  late final ProcessingPauseThreshold pauseThreshold;
  late final ProcessingProcessThreshold processThreshold;
  late final ProcessingSetBpmProcessing setBpmProcessing;
  late final ProcessingPrepareForSignalDrawing prepareForSignalDrawing;
  late final ProcessingCleanup cleanup;
  
  late final ProcessingGetInformation getInformation;

  ProcessingBindings(DynamicLibrary dynamicLibrary) {
    // _lib ??= _loadLibrary();
    print("INIT BINDINGS START");
    _lib = dynamicLibrary;
    _instance = this;
    _initBindings();
  }
  // final ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
  //     _lookup;

  /// The symbols are looked up in [dynamicLibrary].
  // NativeAddBindings(ffi.DynamicLibrary dynamicLibrary)
  //     : _lookup = dynamicLibrary.lookup;

  // /// The symbols are looked up with [lookup].
  // NativeAddBindings.fromLookup(
  //     ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
  //         lookup)
  //     : _lookup = lookup;
  static ProcessingBindings get instance {
    // _instance ??= ProcessingBindings();
    return _instance!;
  }

  void _initBindings() {
    init = _lib!.lookupFunction<ProcessingInitNative, ProcessingInit>('processing_init');

    setSampleRate = _lib!.lookupFunction<ProcessingSetSampleRateNative, ProcessingSetSampleRate>('processing_set_sample_rate');

    setChannelCount = _lib!.lookupFunction<ProcessingSetChannelCountNative, ProcessingSetChannelCount>('processing_set_channel_count');

    setBitsPerSample = _lib!.lookupFunction<ProcessingSetBitsPerSampleNative, ProcessingSetBitsPerSample>('processing_set_bits_per_sample');

    setSelectedChannel = _lib!.lookupFunction<ProcessingSetSelectedChannelNative, ProcessingSetSelectedChannel>('processing_set_selected_channel');

    setBandFilter = _lib!.lookupFunction<ProcessingSetBandFilterNative, ProcessingSetBandFilter>('processing_set_band_filter');

    setNotchFilter = _lib!.lookupFunction<ProcessingSetNotchFilterNative,ProcessingSetNotchFilter>('processing_set_notch_filter');

    processMicrophoneStream = _lib!.lookupFunction<ProcessingProcessMicrophoneStreamNative,ProcessingProcessMicrophoneStream>('processing_process_microphone_stream');
    processSampleStream = _lib!.lookupFunction<ProcessingProcessSampleStreamNative,ProcessingProcessSampleStream>('processing_process_sample_stream');

    // filterData = _lib!.lookupFunction<ProcessingFilterDataNative, ProcessingFilterData>('processing_filter_data');

    rms = _lib!.lookupFunction<ProcessingRmsNative, ProcessingRms>('processing_rms');

    map = _lib!.lookupFunction<ProcessingMapNative, ProcessingMap>('processing_map');

    processFft = _lib!.lookupFunction<ProcessingProcessFftNative, ProcessingProcessFft>('processing_process_fft');

    resetFftNormalization = _lib!.lookupFunction<ProcessingResetFftNormalizationNative, ProcessingResetFftNormalization>('processing_reset_fft_normalization');

    isAudioStreamAmModulated = _lib!.lookupFunction<ProcessingIsAudioStreamAmModulatedNative, ProcessingIsAudioStreamAmModulated>('processing_is_audio_stream_am_modulated');

    getAveragedSampleCount = _lib!.lookupFunction<ProcessingGetAveragedSampleCountNative, ProcessingGetAveragedSampleCount>('processing_get_averaged_sample_count');

    setAveragedSampleCount = _lib!.lookupFunction<ProcessingSetAveragedSampleCountNative, ProcessingSetAveragedSampleCount>('processing_set_averaged_sample_count');

    getAveragingTriggerType = _lib!.lookupFunction<ProcessingGetAveragingTriggerTypeNative, ProcessingGetAveragingTriggerType>('processing_get_averaging_trigger_type');

    setAveragingTriggerType = _lib!.lookupFunction<ProcessingSetAveragingTriggerTypeNative, ProcessingSetAveragingTriggerType>('processing_set_averaging_trigger_type');

    setThreshold = _lib!.lookupFunction<ProcessingSetThresholdNative, ProcessingSetThreshold>('processing_set_threshold');

    resetThreshold = _lib!.lookupFunction<ProcessingResetThresholdNative, ProcessingResetThreshold>('processing_reset_threshold');

    resumeThreshold = _lib!.lookupFunction<ProcessingResumeThresholdNative, ProcessingResumeThreshold>('processing_resume_threshold');

    pauseThreshold = _lib!.lookupFunction<ProcessingPauseThresholdNative, ProcessingPauseThreshold>('processing_pause_threshold');

    processThreshold = _lib!.lookupFunction<ProcessingProcessThresholdNative, ProcessingProcessThreshold>('processing_process_threshold');

    setBpmProcessing = _lib!.lookupFunction<ProcessingSetBpmProcessingNative, ProcessingSetBpmProcessing>('processing_set_bpm_processing');

    prepareForSignalDrawing = _lib!.lookupFunction<ProcessingPrepareForSignalDrawingNative, ProcessingPrepareForSignalDrawing>('processing_prepare_for_signal_drawing');
    
    getInformation = _lib!.lookupFunction<ProcessingGetInformationNative, ProcessingGetInformation>('processing_get_information');

    cleanup = _lib!.lookupFunction<ProcessingCleanupNative, ProcessingCleanup>('processing_cleanup');
  }

  // static DynamicLibrary _loadLibrary() {
  //   String libraryPath = _getLibraryPath();
  //   print('Loading processing plugin from: $libraryPath');
  //   try {
  //     return DynamicLibrary.open(libraryPath);
  //   } catch (e) {
  //     print('Failed to load library: $e');
  //     print('Current working directory: ${Directory.current.path}');
  //     rethrow;
  //   }
  // }

  // static String _getLibraryPath() {
  //   final buildMode = _isDebugMode ? 'Debug' : 'Release';

  //   // Get the absolute path to the project root
  //   final String projectRoot = Directory.current.path;
  //   print('Project root: $projectRoot');

  //   if (Platform.isWindows) {
  //           //return 'build/windows/runner/$buildMode/processing_plugin.dll';
  //           return path.join(projectRoot, 'lib', 'native', 'processing.dll');
  //   } else if (Platform.isMacOS) {
  //     // Try multiple approaches to find the library

  //     // Option 1: Try to load from lib/native directory (new preferred location)
  //     final nativeLibPath =
  //         path.join(projectRoot, 'lib', 'native', 'libprocessing.dylib');

  //     // Option 2: Try to use absolute path to the app bundle framework
  //     final appBundlePath = path.join(
  //         projectRoot,
  //         'build',
  //         'macos',
  //         'Build',
  //         'Products',
  //         buildMode,
  //         'spikerbox_architecture.app',
  //         'Contents',
  //         'Frameworks',
  //         'processing_plugin.framework',
  //         'processing_plugin');

  //     // Option 3: Try the path that was used during build
  //     final buildPath = path.join(
  //         projectRoot,
  //         'build',
  //         'macos',
  //         'Build',
  //         'Products',
  //         buildMode,
  //         'processing_plugin.framework',
  //         'processing_plugin');

  //     // Option 4: Try the path to the dylib directly in the plugin directory
  //     final pluginDyLibPath = path.join(projectRoot, 'native_implementation',
  //         'pluggins', 'processing_plugin', 'libprocessing.dylib');

  //     print('Checking paths:');
  //     print('Native lib path: $nativeLibPath');
  //     print('App bundle path: $appBundlePath');
  //     print('Build path: $buildPath');
  //     print('Plugin dylib path: $pluginDyLibPath');

  //     // Check each path in order
  //     if (File(nativeLibPath).existsSync()) {
  //       print('Found library at native lib path');
  //       return nativeLibPath;
  //     }

  //     if (File(appBundlePath).existsSync()) {
  //       print('Found library at app bundle path');
  //       return appBundlePath;
  //     }

  //     if (File(buildPath).existsSync()) {
  //       print('Found library at build path');
  //       return buildPath;
  //     }

  //     if (File(pluginDyLibPath).existsSync()) {
  //       print('Found library at plugin dylib path');
  //       return pluginDyLibPath;
  //     }

  //     // If we couldn't find it with absolute paths, throw an error with detailed information
  //     throw Exception(
  //         'Could not find processing library in any of the expected locations:\n'
  //         '- $nativeLibPath\n'
  //         '- $appBundlePath\n'
  //         '- $buildPath\n'
  //         '- $pluginDyLibPath\n'
  //         'Please ensure the library is built and in one of these locations.');
  //   } else if (Platform.isLinux) {
  //     return 'build/linux/x64/${buildMode.toLowerCase()}/libprocessing_plugin.so';
  //   }
  //   throw UnsupportedError('Unsupported platform for processing plugin');
  // }

  static void setDebugMode(bool isDebug) {
    _isDebugMode = isDebug;
  }
}
