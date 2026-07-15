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

processingSerialDataResult
flutter: Sample Count  0 : 166 | Channel Count 1 : 166 || Data Length : 166
flutter: Channel Value 0 : -5149 | Channel Value 1 : -5149

C++
Channel 1 Length - 166 | Channel 2 Length 166
Channel 1 Value - -5149 | Channel 2 Value 0



flutter: \r\n
flutter: Sublist ||| Array 0,0 : 19 | Sublist Array 1,0 : 0
flutter: Sublist LENGTH ||| Array 0,0 : 168 | Sublist Array 1,0 : 168

flutter: Sample Count  0 : 168 | Channel Count 1 : 168 || Data Length : 168
flutter: Channel Value 0 : 11539 | Channel Value 1 : 11538

Channel 1 Length - 168 | Channel 2 Length 168
Channel 1 Value - 11539 | Channel 2 Value -23584


flutter: \r\n
flutter: Sublist ||| Array 0,0 : 0 | Sublist Array 1,0 : 0
flutter: Sublist LENGTH ||| Array 0,0 : 166 | Sublist Array 1,0 : 166
flutter: Sample Count  0 : 166 | Channel Count 1 : 166 || Data Length : 166
flutter: Channel Value 0 : 11520 | Channel Value 1 : 11518
Channel 1 Length - 166 | Channel 2 Length 166
Channel 1 Value - 11520 | Channel 2 Value 0

1:960665500990:android:f77af23f5db291f8





       modified:   lib/main.dart
        modified:   lib/models/nwbfile_utils/nwbfile_utils.dart
        modified:   lib/models/nwbfile_utils/nwbfile_utils_native.dart
        modified:   lib/models/nwbfile_utils/nwbfile_utils_web.dart
        modified:   lib/models/processing_utils/processing_util_web.dart
        modified:   lib/screen/graph_template.dart
        modified:   web/index.html
        modified:   web/index.js
        modified:   web/workerSimulation.js


The logic behind seeking file using NWB:



Delete after saving, cookies

Device GAIN LIST:
https://github.com/BackyardBrains/Spike-Recorder/blob/66b1cb83266ad7770a8c6ff5ae4d925a262693ab/src/engine/RecordingManager.cpp#L2910


https://github.com/search?q=repo%3ABackyardBrains%2FSpike-Recorder+gain&type=code&p=1
https://github.com/search?q=repo%3ABackyardBrains%2FSpike-Recorder+ampScale&type=code
https://github.com/BackyardBrains/Spike-Recorder/blob/66b1cb83266ad7770a8c6ff5ae4d925a262693ab/src/AnalysisAudioView.cpp#L55



https://github.com/BackyardBrains/Spike-Recorder/blob/66b1cb83266ad7770a8c6ff5ae4d925a262693ab/src/AudioView.cpp#L442C1-L466C2


[WORKING] WHEN SERIAL RUN, MICROPHONE PAUSE IT
[WORKING] CRASH WHEN changing 3 channels serial to microphone
[WORKING] EVENT from device

flutter run -d windows --verbose 2>&1 | Select-String -Pattern "error|Error|ERROR|fail|Fail|FAIL" -Context 3 | Select-Object -Last 50


Flow layout for channels every 2 channels



[WORKING] Disconnect
[Working] file path
[Working] recording time
[Working] Zoom + and -
Popup channel settings
color selector


flutter build web --no-tree-shake-icons
flutter build macos --no-tree-shake-icons
flutter build apk --no-tree-shake-icons

NeuronSpikerBox 
#Serial stream data
#Serial playback file



message identifier : 
brew install --cask ftdi-vcp-driver



https://devanlai.github.io/webdfu/dfu-util/


dart pub cache clean
flutter pub get

Threshold fix:
increase the buffer

rm -f web/main.dart.js web/main.dart.js_1.part.js web/main.dart.js_2.part.js web/main.dart.js_3.part.js
rm -rf .dart_tool/flutter_build build/web
rm -f ~/.pub-cache/hosted/pub.dev/.cache/*-advisories.json   # if pub get fails
flutter pub get
flutter build web --no-tree-shake-icons


flutter build ios --no-tree-shake-icons

com.backyardbrains.srflutterios


com.backyardbrains.Backyard-Brains


disconnect issue


final row = nwb.nwbfileAddEvent(1.234, 3);
nwb.nwbfileUpdateEvent(row, 1.500, 5);
nwb.nwbfileDeleteEvent(row);