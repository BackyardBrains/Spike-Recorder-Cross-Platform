# spikerbox_flutter


using old Flutter
check if the speed is the same,
displaystream update all the data


byb-lib
dr_wav.c
dr_wav.h

jni-helper.c/h



device init, init level median.
setIsThresholding bindings



The setChannelFilterEnabled method was being optimized away by the compiler because it was considered "unused" or "dead code". Even though the method was:
✅ Declared in the header file
✅ Implemented in the source file
✅ Called from other code
✅ Compiling successfully when built manually



Previous Issue when drawing FFT is because the memory is not using the correct address,
// WRONG IN THIS PART
// buffer[counter++] = (buffer[i].buffer.asFloat32List(0, windowSize));



// RECORDING

// LOADING

// PLAYBACK
pauseButton
// Stopping Audio Playback
GraphTemplate.isLoadingFile = 2; // standby mode to draw the current state, scrub also end at this state
// Playing Audio




Find out why it is crashing
InjectDataResult from loadedFile


loadedArrSamples is the sliced part of the result


Sublist
flutter: Sublist ||| Array 0, 0 : 227 | Sublist Array 1, 0 : 0
flutter: Sample Count  0 : 166 | Channel Count 1 : 166 || Data Length : 166
flutter: Channel Value 0 : -5149 | Channel Value 1 : -5149
Channel 1 Length - 166 | Channel 2 Length 166
Channel 1 Value - -5149 | Channel 2 Value 0