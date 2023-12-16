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
      mWorker.postMessage(
        {
          message: "INITIALIZE_WORKER",
          simulationWorkerChannelPort: workerChannel.port1,
        },
        [workerChannel.port1]
      );
    }
    if (event.data.message === "onWebApplyFilter") {
      window.onProcessingDone(event.data.channelIdx);
    }

    if (event.data.message === "dataBufferAllocation") {
      // Share the typed view of allocated buffer with Dart

      window.onDataBufferAllocated(event.data.dataBuffer, event.data.chIdx);
    }
    // Listening to messages
    workerChannel.port2.onmessage = function (event) { };
  };
}

// init highPassFilter

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


// init lowPassFilter

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


function sendToWebInitNotchFilter(
  channelCount,
  sampleRate,
  cutOffFrequency,
  q
) {
  // Create an object to hold the message data
  const messageData = {
    message: "webInitNotchFilter",
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
  sampleCount,
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
    sampleCount: sampleCount,
  };

  // Send the message to the web worker
  mWorker.postMessage(messageData);
}

