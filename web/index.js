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
    if (event.data.message === "ALLOCATE_DRAWING_DATA_BUFFER") {
      let drawingCountBufferList = event.data.drawingCountBufferList;
      let drawingDataBufferList = event.data.drawingDataBufferList;
      let channelCount = event.data.channelCount;
      let eventPositions = event.data.eventPositions;

      console.log("drawingDataBufferList: ", drawingDataBufferList);
      window.onDrawingBufferAllocated(drawingDataBufferList, drawingCountBufferList, channelCount);
      window.onEventPositionAllocated(eventPositions);
    } else
    if (event.data.message === "SERIAL_DATA_TRANSFER") {
      let frameCount = event.data.frameCount;
      window.onSerialParsedCallback(frameCount);
    } else
    if (event.data.message === "EVENT_FOUND") {
      window.onEventFound(event.data.sampleIndex, event.data.eventLabel);
    } else
    if (event.data.message === "onWebApplyFilter") {
      window.onProcessingDone(event.data.channelIdx);
    } else
    if (event.data.message === "dataBufferAllocation") {
      // Share the typed view of allocated buffer with Dart
      window.onDataBufferAllocated(event.data.dataBuffer, event.data.chIdx);
    } else
    if (event.data.message === "INPUT_MICROPHONE_BUFFER_FINISHED") { 
      window.onPostDisplay(event.data.bufferViews, event.data.bufferCountViews);
      window.onEventPositionCalculated();
    } else
    if (event.data.message === "SET_EXPANSION_BOARD_TYPE") { 
      console.log("event.data.expansionBoardType: ", event.data.expansionBoardType);
      window.setExpansionBoardTypeDart(event.data.expansionBoardType);
    } else
    if (event.data.message === "INPUT_SERIAL_BUFFER_FINISHED") {
      // console.log("INPUT_SERIAL_BUFFER_FINISHED: ", event.data.bufferViews, event.data.bufferCountViews);
      // window.onProcessingDone(event.data.channelIdx, event.data.bufferViews);
      window.onProcessingDone(event.data.bufferViews, event.data.bufferCountViews);
      window.onEventPositionCalculated();
      
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


function initializeMicrophoneWeb(channelCount, sampleRate, drawSurfaceWidth) {
  // console.log("SAMPLE RATE", sampleRate);
  mWorker.postMessage({
    "message": "INITIALIZE_MICROPHONE",
    "channelCount": channelCount,
    "sampleRate": sampleRate,
    "drawSurfaceWidth": drawSurfaceWidth,
  });
}

function prepareDisplayMicrophoneDataWeb(drawSurfaceWidth, channelCount, displayTimeMs, startPositionIdx, endPositionIdx, eventLabels, eventPositions) {
  mWorker.postMessage({
    "message": "DISPLAY_MICROPHONE_DATA",
    "channelCount": channelCount,
    "displayTimeMs": displayTimeMs,
    "drawSurfaceWidth": drawSurfaceWidth,
    "startPositionIdx": startPositionIdx,
    "endPositionIdx": endPositionIdx,
    "eventLabels": eventLabels,
    "eventPositions": eventPositions,

  });
}

function processMicrophoneDataWeb(microphoneDataBuffers, channelIdx, samplesLength) {
  // console.log("processMicrophoneDataWeb", microphoneDataBuffers);
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

function initializeSerialWeb(sampleRate, channelCount, drawSurfaceWidth){
  console.log("Channel Count: ", channelCount, sampleRate);
  if (drawSurfaceWidth === -1) {
    drawSurfaceWidth = window.innerWidth;
  }
  mWorker.postMessage({
    "message": "INITIALIZE_SERIAL",
    "channelCount": parseInt(channelCount),
    "sampleRate": sampleRate,
    "drawSurfaceWidth": drawSurfaceWidth,
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
function displaySerialDataWeb(displayTimeMs, deviceType, deviceWidth, startPositionIdx, endPositionIdx, eventLabels, eventPositions){
  // console.log("eventPositions: ", eventPositions);
  mWorker.postMessage({
    "message": "DISPLAY_SERIAL_DATA_WEB",
    "channelIdx": 0,
    "displayTimeMs": displayTimeMs,
    "deviceType": deviceType,
    "startPositionIdx": startPositionIdx,
    "endPositionIdx": endPositionIdx,
    // "deviceType": 5,
    "drawSurfaceWidth": window.innerWidth,
    "eventLabels": eventLabels,
    "eventPositions": eventPositions,

  });
}

function setChannelFilterEnabled(channel, enabled) {
  mWorker.postMessage({
    "message": "SET_CHANNEL_FILTER_ENABLED",
    "channelIndex": channel,
    "enabled": enabled,
  });
}