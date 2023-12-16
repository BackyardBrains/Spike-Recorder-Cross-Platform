let workerChannelPort;

let dataArrayStartChannelWise = [];
let ptrDataArrayChannelWise = [];
let dataBufferChannelWise = [];

// Should be same as the length of packet sent from Dart
const packetSize = 2000;

let ptrDataArrayChannel1;
let is50Hertz = 0;

var vm = self;
var tempOnMessage = self.onmessage;
self.onmessage = async function (eventFromMain) {
    switch (eventFromMain.data.message) {

        case "INITIALIZE_WORKER":
            workerChannelPort = eventFromMain.data.simulationWorkerChannelPort;
            for (let i = 0; i < 6; i++) {
                // Allocate data buffer
                let ptrDataArray = Module._malloc(packetSize * Module.HEAP16.BYTES_PER_ELEMENT);
                let dataArrayStart = ptrDataArray / Module.HEAP16.BYTES_PER_ELEMENT;
                let dataBuffer = Module.HEAP16.subarray(dataArrayStart, (dataArrayStart + packetSize));

                if (i == 0) {
                    ptrDataArrayChannel1 = ptrDataArray;
                }

                for (let j = 0; j < 10; j++) {
                    dataBuffer[j] = 10 * j;
                }

                ptrDataArrayChannelWise.push(ptrDataArray);
                dataArrayStartChannelWise.push(dataArrayStart);
                dataBufferChannelWise.push(dataBuffer);
                postMessage({
                    message: "dataBufferAllocation",
                    dataBuffer: dataBuffer,
                    chIdx: i,
                });


            }
            break;

        case "webInitHighPassFilter":
            channelCount = eventFromMain.data.channelCount;
            sampleRate = eventFromMain.data.sampleRate;
            cutOffFrequency = eventFromMain.data.cutOffFrequency;
            q = eventFromMain.data.q;

            var result = Module._initHighPassFilter(channelCount, sampleRate, cutOffFrequency, q);
            break;

        case "webInitLowPassFilter":


            channelCount = eventFromMain.data.channelCount;
            sampleRate = eventFromMain.data.sampleRate;
            cutOffFrequency = eventFromMain.data.cutOffFrequency;
            q = eventFromMain.data.q;
            var result = Module._initLowPassFilter(channelCount, sampleRate, cutOffFrequency, q);
            break;

        case "webInitNotchFilter":
            channelCount = eventFromMain.data.channelCount;
            sampleRate = eventFromMain.data.sampleRate;
            cutOffFrequency = eventFromMain.data.cutOffFrequency;
            q = eventFromMain.data.q;
            is50Hertz = eventFromMain.data.cutOffFrequency == 50 ? 1 : 0;


            var result = Module._initNotchFilter(
                is50Hertz,
                channelCount, sampleRate, cutOffFrequency, q);
            break;


        case "webApplyFilter":
            if (eventFromMain.data.toApplyHighPass) {

                const response = Module.ccall(
                    'applyHighPassFilter',
                    'number', // Assuming the function returns a number (pointer)
                    ['number', 'number', 'number'], // Argument types: int16_t, short*, int32_t
                    [eventFromMain.data.channelIdx, ptrDataArrayChannelWise[eventFromMain.data.channelIdx], eventFromMain.data.sampleCount]
                );
                // console.log("buffer error check");
            }
            if (eventFromMain.data.toApplyLowPass) {
                const response = Module.ccall(
                    'applyLowPassFilter',
                    'number', // Assuming the function returns a number (pointer)
                    ['number', 'number', 'number'], // Argument types: int16_t, short*, int32_t
                    [eventFromMain.data.channelIdx, ptrDataArrayChannelWise[eventFromMain.data.channelIdx], eventFromMain.data.sampleCount]
                );
            }
            if (eventFromMain.data.toApplyNotch) {
                const response = Module.ccall(
                    'applyNotchFilter',
                    'number', // Assuming the function returns a number (pointer)
                    ['number', 'number', 'number', 'number'], // Argument types: int16_t, short*, int32_t
                    [is50Hertz, eventFromMain.data.channelIdx, ptrDataArrayChannelWise[eventFromMain.data.channelIdx], eventFromMain.data.sampleCount]

                );
                console.log("notch filter is running " + response);
            }

            postMessage({
                message: "onWebApplyFilter",
                channelIdx: eventFromMain.data.channelIdx,
            });
            break;

        default:
    }
}

if ('function' === typeof importScripts) {
    self.importScripts("a.out.js");
    self.Module.onRuntimeInitialized = async _ => {

        postMessage({
            message: 'INITIALIZE_WASM',
        });
    };
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}
