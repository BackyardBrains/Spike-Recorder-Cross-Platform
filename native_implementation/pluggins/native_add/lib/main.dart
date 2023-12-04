import 'dart:ffi' as ffi;

/*
*
*
*
* Filtering
*
*
*/
typedef InitHighPassFilterProcess = double Function(
    int, double, double, double);
typedef ApplyHighPassFilter = double Function(int, ffi.Pointer<ffi.Int16>, int);

typedef InitLowPassFilterProcess = double Function(int, double, double, double);
typedef ApplyLowPassFilter = double Function(int, ffi.Pointer<ffi.Int16>, int);

typedef InitNotchPassFilterProcess = double Function(int,
    int, double, double, double);
typedef ApplyNotchPassFilter = double Function(
    int, int, ffi.Pointer<ffi.Int16>, int);

typedef setNotchPassFilterProcess = double Function(int, int);

/*
*
*
*
* Microphone
*
*
*/
typedef CapturedSetAudio = double Function();

typedef example_foo = ffi.Int32 Function(
    ffi.Int32 bar, ffi.Pointer<ffi.NativeFunction<MicCallback>>);
typedef ExampleFoo = int Function(
    int bar, ffi.Pointer<ffi.NativeFunction<MicCallback>>);

typedef MicCallback = ffi.Int32 Function(ffi.Pointer<ffi.Int16>, ffi.Int32);

//  check isDataAvailable
typedef CheckAudioData = double Function(ffi.Pointer<ffi.Int16>);

typedef SetAudioData = double Function(ffi.Pointer<ffi.Int16>);

/// FFI bindings with cpp files
class NativeAddBindings {
  final ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
      _lookup;

  /// The symbols are looked up in [dynamicLibrary].
  NativeAddBindings(ffi.DynamicLibrary dynamicLibrary)
      : _lookup = dynamicLibrary.lookup;

  /// The symbols are looked up with [lookup].
  NativeAddBindings.fromLookup(
      ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
          lookup)
      : _lookup = lookup;

// Mic stream from the window native code
  double listenMic() {
    print("check in native code");
    return _capturingAudio();
  }

  late final CapturedSetAudio _capturingAudio =
      _lookup<ffi.NativeFunction<ffi.Double Function()>>('newlistenMic')
          .asFunction();

  double isAudioCaptureData(ffi.Pointer<ffi.Int16> mPointer) {
    return _isAudioCapture(mPointer);

    // Perform your operations here
  }

  late final CheckAudioData _isAudioCapture = _lookup<
          ffi.NativeFunction<
              ffi.Double Function(
                ffi.Pointer<ffi.Int16>,
              )>>('isCheckData')
      .asFunction();

  /// Call initHighPassFilter to initialise or set filter configuration
  double initHighPassFilter(
      int channelCount, double sampleRate, double cutOff, double q) {
    return _initHighPassFilterProcess(channelCount, sampleRate, cutOff, q);
  }

  late final InitHighPassFilterProcess _initHighPassFilterProcess = _lookup<
          ffi.NativeFunction<
              ffi.Double Function(ffi.Int, ffi.Double, ffi.Double,
                  ffi.Double)>>('initHighPassFilter')
      .asFunction();

  double applyHighPassFilter(
      int channelIndex, ffi.Pointer<ffi.Int16> data, int sampleCount) {
    return _applyHighPassFilter(channelIndex, data, sampleCount);
  }

  late final ApplyHighPassFilter _applyHighPassFilter = _lookup<
          ffi.NativeFunction<
              ffi.Double Function(ffi.Int16, ffi.Pointer<ffi.Int16>,
                  ffi.Uint32)>>('applyHighPassFilter')
      .asFunction();

  /*
  *
  * Low pass filter
  *
  * */

  /// Call applyLowPassFilter to apply filter on every packet
  ///
  /// Modifies and returns the values in the same buffer.

  /// Call initLowPassFilter to initialise or set filter configuration
  double initLowPassFilter(
      int channelCount, double sampleRate, double cutOff, double q) {
    _initLowPassFilterProcess(channelCount, sampleRate, cutOff, q);
    return 1;
  }

  late final InitLowPassFilterProcess _initLowPassFilterProcess = _lookup<
          ffi.NativeFunction<
              ffi.Double Function(ffi.Int, ffi.Double, ffi.Double,
                  ffi.Double)>>('initLowPassFilter')
      .asFunction();

  double applyLowPassFilter(
      int channelIndex, ffi.Pointer<ffi.Int16> data, int sampleCount) {
    return _applyLowPassFilter(channelIndex, data, sampleCount);
  }

  late final ApplyLowPassFilter _applyLowPassFilter = _lookup<
          ffi.NativeFunction<
              ffi.Double Function(ffi.Int16, ffi.Pointer<ffi.Int16>,
                  ffi.Uint32)>>('applyLowPassFilter')
      .asFunction();

  /// notch pass filter to initialise or set notchFilter configuration

  double setNotchPassFilter(int isNotch50, int isNotch60) {
    return _setNotchPassFilter(isNotch50, isNotch60);
  }

  late final setNotchPassFilterProcess _setNotchPassFilter =
      _lookup<ffi.NativeFunction<ffi.Double Function(ffi.Int, ffi.Int)>>(
              'setNotch')
          .asFunction();

          
  double initNotchPassFilter(int isHertz50, int channelCount, double sampleRate,
      double cutOff, double q) {
    _initNotchPassFilterProcess(isHertz50, channelCount, sampleRate, cutOff, q);
    return 1;
  }

  late final InitNotchPassFilterProcess _initNotchPassFilterProcess = _lookup<
          ffi.NativeFunction<
              ffi.Double Function(ffi.Int, ffi.Int, ffi.Double, ffi.Double,
                  ffi.Double)>>('initNotchPassFilter')
      .asFunction();

  double applyNotchPassFilter(int _isNotch50, int channelIndex,
      ffi.Pointer<ffi.Int16> data, int sampleCount) {
    return _applyNotchPassFilter(_isNotch50, channelIndex, data, sampleCount);
  }

  late final ApplyNotchPassFilter _applyNotchPassFilter = _lookup<
          ffi.NativeFunction<
              ffi.Double Function(ffi.Int16, ffi.Int16, ffi.Pointer<ffi.Int16>,
                  ffi.Uint32)>>('applyNotchPassFilter')
      .asFunction();

  ffi.Pointer<ffi.Uint8> multiplyArrayElements(
      ffi.Pointer<ffi.Uint8> array, int length) {
    return _multiplyArrayElements(array, length);
  }

  late final _multiplyArrayElementsPtr = _lookup<
      ffi.NativeFunction<
          ffi.Pointer<ffi.Uint8> Function(
              ffi.Pointer<ffi.Uint8>, ffi.Int64)>>('multiply_array_elements');
  late final _multiplyArrayElements = _multiplyArrayElementsPtr.asFunction<
      ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.Uint8>, int)>();
}
