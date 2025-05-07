// sh /Users/macbook/Documents/...emscriptenFolder.../emcc --bind -O3 --std=c++20 -x c++ LowPassFilter.cpp HighPassFilter.cpp FilterBase.cpp FilterBase.cpp HeartbeatHelper.cpp NotchPassFilter.cpp Processor.cpp ThresholdProcessor.cpp -s TOTAL_MEMORY=536870912 -s EXPORTED_FUNCTIONS="['_malloc']" -s EXPORTED_RUNTIME_METHODS="['ccall']"

//TODO: Use this command to generate a combined WASM
// emcc --bind -O3 --std=c++20 -x c++ low_pass_filter.cpp high_pass_filter.cpp filter_base.cpp main_entry_file.cpp -s TOTAL_MEMORY=536870912 -s EXPORTED_FUNCTIONS="['_malloc']" -s EXPORTED_RUNTIME_METHODS="['ccall']" -pthread -s PROXY_TO_PTHREAD

var mWorker;
let workerChannel;

function initializeModule() {
  try {
    mWorker.terminate();
  } catch (e) { }

  workerChannel = new MessageChannel();
  mWorker = new Worker("workerSimulation.js");

  mWorker.onmessage = function (event) {
    if (event.data.message == "INITIALIZE_WASM") {
      // mWorker.postMessage(
      //   {
      //     message: "INITIALIZE_WORKER",
      //     simulationWorkerChannelPort: workerChannel.port1,
      //   },
      //   [workerChannel.port1]
      // );
    } else
    if (event.data.message === "SERIAL_DATA_TRANSFER") {
      
    } else
    if (event.data.message === "onWebApplyFilter") {
      window.onProcessingDone(event.data.channelIdx);
    } else
    if (event.data.message === "dataBufferAllocation") {
      // Share the typed view of allocated buffer with Dart
      window.onDataBufferAllocated(event.data.dataBuffer, event.data.chIdx);
    } else
    if (event.data.message === "INPUT_MICROPHONE_BUFFER_FINISHED") {
      window.onPostDisplay(1, event.data.bufferViews);
    } else
    if (event.data.message === "INPUT_SERIAL_BUFFER_FINISHED") {
      // console.log("INPUT_SERIAL_BUFFER_FINISHED: ", event.data.channelIdx, event.data.bufferViews.length);
      window.onProcessingDone(event.data.channelIdx, event.data.bufferViews);
    }

    
    // Listening to messages
    workerChannel.port2.onmessage = function (event) { };
  };
}

function sendToWebInitHighPassFilter(
  channelCount,
  sampleRate,
  cutOffFrequency,
  q
) {
  // Create an object to hold the message data
  const messageData = {
    message: "webInitHighPassFilter",
    channelCount: channelCount,
    sampleRate: sampleRate,
    cutOffFrequency: cutOffFrequency,
    q: 0.5,
  };
  // Send the message to the web worker
  mWorker.postMessage(messageData);
  // Optionally, log a message after sending
}

function sendToWebInitLowPassFilter(
  channelCount,
  sampleRate,
  cutOffFrequency,
  q
) {
  // Create an object to hold the message data
  const messageData = {
    message: "webInitLowPassFilter",
    channelCount: channelCount,
    sampleRate: sampleRate,
    cutOffFrequency: cutOffFrequency,
    q: 0.5,
  };

  // Send the message to the web worker
  mWorker.postMessage(messageData);
}

function sendToWorkerApplyFilter(
  channelIdx,
  samples,
  toApplyHighPass,
  toApplyLowPass,
  toApplyNotch
) {
  // Create an object to hold the message data
  const messageData = {
    message: "webApplyFilter",
    toApplyHighPass: toApplyHighPass,
    toApplyLowPass: toApplyLowPass,
    toApplyNotch: toApplyNotch,
    channelIdx: channelIdx,
    samples: samples,
    "drawSurfaceWidth": window.innerWidth,
  };

  // Send the message to the web worker
  mWorker.postMessage(messageData);
}


function initializeMicrophoneWeb(channelCount, sampleRate) {
  mWorker.postMessage({
    "message": "INITIALIZE_MICROPHONE",
    "channelCounts": channelCount,
    "sampleRate": sampleRate,
  });
}

function prepareDisplayMicrophoneDataWeb(drawSurfaceWidth, channelCount, displayTimeMs) {
  mWorker.postMessage({
    "message": "CHANGE_MICROPHONE_CONFIG",
    "channelCount": channelCount,
    "displayTimeMs": displayTimeMs,
    "drawSurfaceWidth": drawSurfaceWidth,
  });
}

function processMicrophoneDataWeb(microphoneDataBuffers, channelIdx, samplesLength) {
  // console.log("processMicrophoneDataWeb");
  // console.log(window.innerWidth);
  mWorker.postMessage({
    "message": "INPUT_MICROPHONE_BUFFER",
    "microphoneDataBuffers": microphoneDataBuffers,
    "channelIdx": channelIdx,
    "samplesLength": samplesLength,
    "drawSurfaceWidth": window.innerWidth,
  });
  // if (isProcessNow) {
  // } else {
  // }
  //   console.log("microphoneDataBuffer");
  //   console.log(microphoneDataBuffer);
}

function setBandFilterWeb(lowFreq, highFreq) {
  mWorker.postMessage({
    "message": "SET_BAND_FILTER",
    "lowFreq": lowFreq,
    "highFreq": highFreq,
  });
}

function setNotchFilterWeb(centerFreq) {
  mWorker.postMessage({
    "message": "SET_NOTCH_FILTER",
    "centerFreq": centerFreq,
  });
}

function initializeSerialWeb(sampleRate, channelCount){
  console.log("Channel Count: ", channelCount, sampleRate);
  mWorker.postMessage({
    "message": "INITIALIZE_SERIAL",
    "channelCount": parseInt(channelCount),
    "sampleRate": sampleRate,
  });
}
function processSerialDataWeb(samples, displayTimeMs, deviceType){
  // console.log("samples: ", samples);
  mWorker.postMessage({
    "message": "SEND_SERIAL_DATA_WEB",
    "samples": samples,
    "channelIdx": 0,
    "displayTimeMs": displayTimeMs,
    "deviceType": deviceType,
    // "deviceType": 5,
    "drawSurfaceWidth": window.innerWidth,
  });
}