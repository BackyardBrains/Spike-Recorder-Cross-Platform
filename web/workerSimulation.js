let workerChannelPort;

let dataArrayStartChannelWise = [];
let ptrDataArrayChannelWise = [];
let dataBufferChannelWise = [];

// Should be same as the length of packet sent from Dart
const packetSize = 2000;

const MAX_EVENT_MARKERS = 2000;
const MAX_DISPLAY_SECONDS = 10;
let packetLen = MAX_DISPLAY_SECONDS;
let ptrDataArrayChannel1;
var currentDataBuffers = [];
var currentDataBuffersPtr;
var eventLabels;
var eventPositions;

var channelCount = 1;
var _displayTimeMs = 10000;
var sampleRate = 44100;
// var sampleRate = 48000;

var vm = self;

var expBoardTypePtr;
var expBoardTypePtrStart;
var expBoardTypeBuffer;

/* PROCESSING */
let drawingDataPtr;
let drawingDataPtrStart;
let drawingDataBuffer;
let drawingDataBufferList;
let drawingDataPtrList;

let drawingCountPtr;
let drawingCountPtrStart;
let drawingCountBuffer;
let drawingCountBufferList;
let drawingCountPtrList;


let outEventPositionPtr;
let outEventPositionPtrStart;
let outEventPositionBuffer;

let serialDataPtr;
let serialDataPtrStart;
let serialDataBuffer;


let data;
let channelIdx;
let inDataPtr;
let inDataPtrStart;
let inDataArr;

let inSamplesPtr;
let inSamplesPtrStart;
let inSamplesBuffer;

let totalChannel;
let outSampleCountsPtr;
let outSampleCountsPtrStart;
let outSampleCountsBuffer;

let drawSurfaceWidth;
let outSignalPtr;
let outSignalPtrStart;
let outSignalBuffer;

let outSamplesPtr;
let outSamplesPtrStart;
let outSamplesBuffer;

let outSampleCountsDrawingPtr;
let outSampleCountsDrawingPtrStart;
let outSampleCountsDrawingBuffer;

let totalEvents;
let outEventIndicesPtr;
let outEventIndicesPtrStart;
let outEventIndicesBuffer;

let totalEventCounts;
let outEventCountPtr;
let outEventCountPtrStart;
let outEventCountBuffer;

let inTotalEvents;
let inEventIndicesPtr;
let inEventIndicesPtrStart;
let inEventIndicesBuffer;
let displayTimeMs;

/*
*/

var tempOnMessage = self.onmessage;
self.onmessage = async function (eventFromMain) {
    switch (eventFromMain.data.message) {
        case "INITIALIZE_MICROPHONE":
            sampleRate = eventFromMain.data.sampleRate;
            channelCount = eventFromMain.data.channelCount;
            drawSurfaceWidth = eventFromMain.data.drawSurfaceWidth;
            console.log("INITIALIZE_MICROPHONE : ", sampleRate, channelCount);
            // sampleRate = eventFromMain.data.sampleRate;
            Module._processing_init();
            // Module._processing_set_channel_count(channelCount);
            let r = Module._processing_set_sample_rate(sampleRate);
            console.log("SAMPLER RATE RES: ", r);
            packetLen = MAX_DISPLAY_SECONDS * sampleRate;
            const packetLen2 = packetLen; //1156;
            // const curBufferPtr = Module._malloc( channelCount * packetLen2 * Module.HEAP16.BYTES_PER_ELEMENT);
            // const curBufferPtrStart = curBufferPtr / Module.HEAP16.BYTES_PER_ELEMENT;
            // currentDataBuffers = Module.HEAP16.subarray(curBufferPtrStart, (curBufferPtrStart + channelCount * packetLen2));

            // DRAWING BUFFER SETUP
            try{
                if (drawingDataPtrList !== undefined){
                    for (let i = 0; i < drawingDataPtrList.length; i++) {
                        Module._free(drawingDataPtrList[i]);
                    }
                }
            }catch(err) {
                console.log(err);
            }

            drawingDataPtrList=[];
            drawingDataBufferList = [];            
            for (let i = 0; i < channelCount; i++) {
                drawingDataPtr = Module._malloc(drawSurfaceWidth * 5 * Module.HEAP16.BYTES_PER_ELEMENT);
                drawingDataPtrStart = drawingDataPtr / Module.HEAP16.BYTES_PER_ELEMENT;
                drawingDataBuffer = Module.HEAP16.subarray(drawingDataPtrStart, (drawingDataPtrStart + drawSurfaceWidth * 5));
                drawingDataPtrList.push(drawingDataPtr);
                drawingDataBufferList.push(drawingDataBuffer);
            }

            console.log("onDrawingBufferAllocated - javascript", channelCount, drawingDataBufferList, drawSurfaceWidth);
            // END DRAWING BUFFER SETUP

            // DRAWING COUNTER SETUP
            try{
                if (drawingCountPtrList !== undefined){
                    for (let i = 0; i < drawingCountPtrList.length; i++) {
                        Module._free(drawingCountPtrList[i]);
                    }
                }
            }catch(err) {
                console.log(err);
            }

            drawingCountPtrList=[];
            // drawingCountBufferList = [];            
            let i = 0;
            drawingCountPtr = Module._malloc(channelCount * Module.HEAP16.BYTES_PER_ELEMENT);
            drawingCountPtrStart = drawingCountPtr / Module.HEAP16.BYTES_PER_ELEMENT;
            drawingCountBuffer = Module.HEAP16.subarray(drawingCountPtrStart, (drawingCountPtrStart + channelCount));
            drawingCountPtrList.push(drawingCountPtr);
            drawingCountBufferList = (drawingCountBuffer);


            outEventPositionPtr = Module._malloc(MAX_EVENT_MARKERS * Module.HEAPF64.BYTES_PER_ELEMENT);
            outEventPositionPtrStart = outEventPositionPtr / Module.HEAPF64.BYTES_PER_ELEMENT;
            outEventPositionBuffer = Module.HEAPF64.subarray(outEventPositionPtrStart, (outEventPositionPtrStart + MAX_EVENT_MARKERS));
            for (i = 0; i < channelCount; i++) {
                drawingCountBuffer[i] = drawSurfaceWidth * 5;
            }
            console.log("onDrawingBufferAllocated - javascript", channelCount, drawingCountBufferList, drawSurfaceWidth);
            postMessage({
                "message": "ALLOCATE_DRAWING_DATA_BUFFER",
                "drawingDataBufferList": drawingDataBufferList,
                "drawingCountBufferList": drawingCountBufferList,
                "channelCount": channelCount,
                "eventPositions": outEventPositionBuffer,
            });
            // END DRAWING COUNTER SETUP            

            // currentDataBuffersPtr = curBufferPtr;
            console.log("Module: ", Module);
        break;
        case "INITIALIZE_WORKER":
            workerChannelPort = eventFromMain.data.simulationWorkerChannelPort;

        break;
        case "DISPLAY_MICROPHONE_DATA":
            // _drawSurfaceWidth = eventFromMain.data.drawSurfaceWidth;
            channelCount = eventFromMain.data.channelCount;
            _displayTimeMs = eventFromMain.data.displayTimeMs;
            drawSurfaceWidth = eventFromMain.data.drawSurfaceWidth;
            startPositionIdx = eventFromMain.data.startPositionIdx;
            endPositionIdx = eventFromMain.data.endPositionIdx;
            eventLabels = JSON.parse(eventFromMain.data.eventLabels);
            eventPositions = JSON.parse(eventFromMain.data.eventPositions);

            
            outSignalPtr = Module._malloc(drawSurfaceWidth * 5 * totalChannel * Module.HEAP32.BYTES_PER_ELEMENT);
            outSignalPtrStart = outSignalPtr / Module.HEAP32.BYTES_PER_ELEMENT;
            outSignalBuffer = Module.HEAP32.subarray(outSignalPtrStart, (outSignalPtrStart + drawSurfaceWidth * 5));
            
            outSamplesPtr = Module._malloc(drawSurfaceWidth * 5 * totalChannel * Module.HEAP16.BYTES_PER_ELEMENT);
            outSamplesPtrStart = outSamplesPtr / Module.HEAP16.BYTES_PER_ELEMENT;
            outSamplesBuffer = Module.HEAP16.subarray(outSamplesPtrStart, (outSamplesPtrStart + drawSurfaceWidth * 5 * totalChannel));

            outSampleCountsDrawingPtr = Module._malloc( totalChannel * Module.HEAP32.BYTES_PER_ELEMENT);
            outSampleCountsDrawingPtrStart = outSampleCountsDrawingPtr / Module.HEAP32.BYTES_PER_ELEMENT;
            outSampleCountsDrawingBuffer = Module.HEAP32.subarray(outSampleCountsDrawingPtrStart, (outSampleCountsDrawingPtrStart + totalChannel));

            totalEvents = eventLabels.length;
            outEventIndicesPtr = Module._malloc( totalEvents * Module.HEAPF32.BYTES_PER_ELEMENT);
            outEventIndicesPtrStart = outEventIndicesPtr / Module.HEAPF32.BYTES_PER_ELEMENT;
            outEventIndicesBuffer = Module.HEAPF32.subarray(outEventIndicesPtrStart, (outEventIndicesPtrStart + totalEvents));

            totalEventCounts = 1;
            outEventCountPtr = Module._malloc( totalEvents * Module.HEAP32.BYTES_PER_ELEMENT);
            outEventCountPtrStart = outEventCountPtr / Module.HEAP32.BYTES_PER_ELEMENT;
            outEventCountBuffer = Module.HEAP32.subarray(outEventCountPtrStart, (outEventCountPtrStart + totalEventCounts));

            inTotalEvents = eventLabels.length;
            inEventIndicesPtr = Module._malloc( inTotalEvents * Module.HEAP32.BYTES_PER_ELEMENT);
            inEventIndicesPtrStart = inEventIndicesPtr / Module.HEAP32.BYTES_PER_ELEMENT;
            inEventIndicesBuffer = Module.HEAP32.subarray(inEventIndicesPtrStart, (inEventIndicesPtrStart + inTotalEvents));
            displayTimeMs = _displayTimeMs;
            // console.log("eventLabels: ", eventLabels.length, eventPositions);
            if (inTotalEvents > 0) {
                inEventIndicesBuffer.set(eventPositions);
            }
            // console.log("inEventIndicesBuffer: ", inEventIndicesBuffer, eventPositions);

            // console.log("drawing");
            outSampleCountsDrawingBuffer[0] = drawSurfaceWidth * 5;
            try {
              
                let resultDrawing = Module._processing_prepare_for_signal_drawing(
                    outSamplesPtr,           // Pointer<Pointer<Float>>
                    // currentDataBuffersPtr,           // Pointer<Pointer<Float>>
                    outSampleCountsDrawingPtr,      // Pointer<Int32>
                    outEventIndicesPtr,      // Pointer<Float>
                    outEventCountPtr,        // Pointer<Int32>
                    inEventIndicesPtr,       // Pointer<Int32>
                    inTotalEvents,                       // int (inEventCount)

                    // 0,                       // int (fromSample)
                    // Math.floor(displayTimeMs * 0.001 * sampleRate),  // int (toSample)
                    startPositionIdx,                       // int (fromSample)
                    endPositionIdx,  // int (toSample)
                    drawSurfaceWidth         // int
                );

                // console.log("resultDrawing: ", channelCount, resultDrawing, outSamplesBuffer);
                if (resultDrawing == 0) {
                    if (inTotalEvents > 0) {
                        // let float64list = convertFloat32ToFloat64(outEventIndicesBuffer, outEventPositionBuffer);
                        // outEventPositionBuffer.set(float64list);

                        outEventPositionBuffer.set(outEventIndicesBuffer.subarray(0, inTotalEvents));
                        // // outEventPositionBuffer.fill(200.0, 0);
                        // let len = outEventCountBuffer[0];
                        // console.log("outEventIndicesBuffer", outEventIndicesBuffer.subarray(0, inTotalEvents), inEventIndicesBuffer.subarray(0, inTotalEvents));
                    }
                    try{
                        // console.log("Channel Count: " , channelCount);
                        for (let i = 0; i < channelCount; i++) {
                            const outSampleCount = outSampleCountsDrawingBuffer[i];
                            const slicedArray = outSamplesBuffer.subarray( i * outSampleCount, (i + 1) * outSampleCount).slice();
                            const slicedCountArray = outSampleCountsBuffer.subarray(i, i + 1).slice();
                            // console.log("drawingCountBufferList: ", slicedCountArray[0], slicedArray.length);
                            drawingDataBufferList[i].set(slicedArray, 0);
                            drawingCountBufferList[i] = slicedArray.length;
                        }
                        // console.log("drawingCountBufferList: ", drawingCountBufferList);
                        const data = {
                            "message": "INPUT_MICROPHONE_BUFFER_FINISHED",
                            "channelIdx": 0,
                            "bufferViews": drawingDataBufferList,
                            "bufferCountViews": drawingCountBufferList,
                        };
                        postMessage(data);
                    }catch(err) {

                    }
    
                    // for (let idx = 0; idx < totalChannel; idx++) {
                    //     const slicedArray = outSamplesBuffer.subarray(0, outSampleCountsDrawingBuffer[idx]).slice();
                    //     postMessage({
                    //         "message": "INPUT_MICROPHONE_BUFFER_FINISHED",
                    //         "channelIdx": idx,
                    //         "bufferViews": slicedArray,
                    //     });
                    // }
                }

                Module._free(outSignalPtr);
                Module._free(outSamplesPtr);
                Module._free(outSampleCountsDrawingPtr);
                Module._free(outEventIndicesPtr);
                Module._free(outEventCountPtr);
                Module._free(inEventIndicesPtr);
            }catch(err){
                console.log("err");
                console.log(err);
            } finally {
            }            
        break;
        case "INPUT_MICROPHONE_BUFFER":
            // Prepare input data pointer
            data = eventFromMain.data.microphoneDataBuffers;
            channelIdx = eventFromMain.data.channelIdx;
            inDataPtr = Module._malloc(data.length * Module.HEAPU8.BYTES_PER_ELEMENT);
            inDataPtrStart = inDataPtr / Module.HEAPU8.BYTES_PER_ELEMENT;
            inDataArr = Module.HEAPU8.subarray(inDataPtrStart, (inDataPtrStart + data.length));
            
            inSamplesPtr = Module._malloc( packetLen * Module.HEAP16.BYTES_PER_ELEMENT);
            inSamplesPtrStart = inSamplesPtr / Module.HEAP16.BYTES_PER_ELEMENT;
            inSamplesBuffer = Module.HEAP16.subarray(inSamplesPtrStart, (inSamplesPtrStart + packetLen));

            totalChannel = channelCount;
            outSampleCountsPtr = Module._malloc( totalChannel * Module.HEAP32.BYTES_PER_ELEMENT);
            outSampleCountsPtrStart = outSampleCountsPtr / Module.HEAP32.BYTES_PER_ELEMENT;
            outSampleCountsBuffer = Module.HEAP32.subarray(outSampleCountsPtrStart, (outSampleCountsPtrStart + totalChannel));

            for (let i = 0; i < totalChannel; i++) {
                outSampleCountsBuffer[i] = data.length / 2;
            }
            inDataArr.set(data);

            const micResult = Module._processing_process_microphone_stream(
                inSamplesPtr,
                outSampleCountsPtr,
                inDataPtr,
                data.length
            );
            

            Module._free(inSamplesPtr);
            Module._free(inDataPtr);
            Module._free(outSampleCountsPtr);
            if (micResult >= 0) {
            }
            // console.log("micResult: ", micResult);
        

        break;
        case "SET_CHANNEL_FILTER_ENABLED":
            const channelIndex = eventFromMain.data.channelIndex;
            const enabled = eventFromMain.data.enabled == 1 ? true : false;
            console.log("_processing_set_channel_filter_enabled WEB ", channelIndex, enabled);
            Module._processing_set_channel_filter_enabled(channelIndex, enabled);

        break;

        case "SET_BAND_FILTER":
            const lowFreq = eventFromMain.data.lowFreq;
            const highFreq = eventFromMain.data.highFreq;
            console.log("lowFreq, highFreq");
            console.log(lowFreq, highFreq);
            Module._processing_set_band_filter(lowFreq, highFreq);
        break;
        case "SET_NOTCH_FILTER":
            const centerFreq = eventFromMain.data.centerFreq;
            console.log("SET NOTCH FILTER", centerFreq);
            let res = Module._processing_set_notch_filter(centerFreq);
            console.log(res);
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
        case "INITIALIZE_SERIAL":
            Module._processing_init();
            console.log("INITIALIZE_SERIAL: ", eventFromMain.data);
            channelCount = eventFromMain.data.channelCount;
            sampleRate = eventFromMain.data.sampleRate;
            drawSurfaceWidth = eventFromMain.data.drawSurfaceWidth;

            packetLen = sampleRate * MAX_DISPLAY_SECONDS;
            Module._processing_set_sample_rate(sampleRate);
            Module._processing_set_channel_count(channelCount);
            // Module._processing_set_bits_per_sample(14);
            expBoardTypePtr = Module._malloc(1 * Module.HEAP16.BYTES_PER_ELEMENT);
            expBoardTypePtrStart = expBoardTypePtr / Module.HEAP16.BYTES_PER_ELEMENT;
            expBoardTypeBuffer = Module.HEAP16.subarray( expBoardTypePtrStart, (expBoardTypePtrStart + 1) );
            expBoardTypeBuffer[0] = -1;
            console.log("Module");
            // console.log(Module.ccall);
            // Module._processing_pass_pointers(expBoardTypePtr);
            const test = Module.ccall(
                'processing_pass_pointers',
                'number',
                [
                    'number', 
                ],
                [
                    expBoardTypePtr
                ]
            );            
            

            // DRAWING BUFFER SETUP
            try{
                if (drawingDataPtrList !== undefined){
                    for (let i = 0; i < drawingDataPtrList.length; i++) {
                        Module._free(drawingDataPtrList[i]);
                    }
                }
            }catch(err) {
                console.log(err);
            }

            drawingDataPtrList=[];
            drawingDataBufferList = [];            
            for (let i = 0; i < channelCount; i++) {
                drawingDataPtr = Module._malloc(drawSurfaceWidth * 5 * Module.HEAP16.BYTES_PER_ELEMENT);
                drawingDataPtrStart = drawingDataPtr / Module.HEAP16.BYTES_PER_ELEMENT;
                drawingDataBuffer = Module.HEAP16.subarray(drawingDataPtrStart, (drawingDataPtrStart + drawSurfaceWidth * 5));
                drawingDataPtrList.push(drawingDataPtr);
                drawingDataBufferList.push(drawingDataBuffer);
            }
            console.log("onDrawingBufferAllocated - javascript", channelCount, drawingDataBufferList, drawSurfaceWidth);
            // END DRAWING BUFFER SETUP

            // DRAWING COUNTER SETUP
            try{
                if (drawingCountPtrList !== undefined){
                    for (let i = 0; i < drawingCountPtrList.length; i++) {
                        Module._free(drawingCountPtrList[i]);
                    }
                }
            }catch(err) {
                console.log(err);
            }

            drawingCountPtrList=[];
            // drawingCountBufferList = [];            
            drawingCountPtr = Module._malloc(channelCount * Module.HEAP16.BYTES_PER_ELEMENT);
            drawingCountPtrStart = drawingCountPtr / Module.HEAP16.BYTES_PER_ELEMENT;
            drawingCountBuffer = Module.HEAP16.subarray(drawingCountPtrStart, (drawingCountPtrStart + channelCount));
            drawingCountPtrList.push(drawingCountPtr);
            drawingCountBufferList = (drawingCountBuffer);


            inEventPositionPointer = Module._malloc(MAX_EVENT_MARKERS * Module.HEAP32.BYTES_PER_ELEMENT);
            inEventPositionPointerStart = inEventPositionPointer / Module.HEAP32.BYTES_PER_ELEMENT;
            inEventPositionPointerBuffer = Module.HEAP32.subarray(inEventPositionPointerStart, (inEventPositionPointerStart + MAX_EVENT_MARKERS));

            outEventPositionPtr = Module._malloc(MAX_EVENT_MARKERS * Module.HEAPF64.BYTES_PER_ELEMENT);
            outEventPositionPtrStart = outEventPositionPtr / Module.HEAPF64.BYTES_PER_ELEMENT;
            outEventPositionBuffer = Module.HEAPF64.subarray(outEventPositionPtrStart, (outEventPositionPtrStart + MAX_EVENT_MARKERS));

            for (let i = 0; i < channelCount; i++) {
                drawingCountBuffer[i] = drawSurfaceWidth * 5;
            }
            console.log("onDrawingBufferAllocated - javascript", channelCount, drawingCountBufferList, drawSurfaceWidth);
            postMessage({
                "message": "ALLOCATE_DRAWING_DATA_BUFFER",
                "drawingDataBufferList": drawingDataBufferList,
                "drawingCountBufferList": drawingCountBufferList,
                "channelCount": channelCount,
                "eventPositions": outEventPositionBuffer,
            });
            // END DRAWING COUNTER SETUP            





            // serialDataPtr = Module._malloc(data.length * Module.HEAPU8.BYTES_PER_ELEMENT);
            // serialDataPtrStart = serialDataPtr / Module.HEAPU8.BYTES_PER_ELEMENT;
            // serialDataBuffer = Module.HEAPU8.subarray(inDataPtrStart, (inDataPtrStart + data.length));

            // postMessage({
            //     "message": "SERIAL_DATA_TRANSFER",
            //     "serialDataBuffer": serialDataBuffer
            // });
        break;
        case "SEND_SERIAL_DATA_WEB":
            data = eventFromMain.data.samples;
            _displayTimeMs = eventFromMain.data.displayTimeMs;
            displayTimeMs = eventFromMain.data.displayTimeMs;

            // console.log("WEBAPPLYFILTER: ", _displayTimeMs);
            channelIdx = eventFromMain.data.channelIdx;

            inDataPtr = Module._malloc(data.length * Module.HEAPU8.BYTES_PER_ELEMENT);
            inDataPtrStart = inDataPtr / Module.HEAPU8.BYTES_PER_ELEMENT;
            inDataArr = Module.HEAPU8.subarray(inDataPtrStart, (inDataPtrStart + data.length));
            
            drawSurfaceWidth = eventFromMain.data.drawSurfaceWidth;
            const serialPacketLen = drawSurfaceWidth * 5;
            // const serialPacketLen = MAX_DISPLAY_SECONDS * sampleRate;
            inSamplesPtr = Module._malloc( serialPacketLen * Module.HEAP16.BYTES_PER_ELEMENT);
            inSamplesPtrStart = inSamplesPtr / Module.HEAP16.BYTES_PER_ELEMENT;
            inSamplesBuffer = Module.HEAP16.subarray(inSamplesPtrStart, (inSamplesPtrStart + serialPacketLen));

            totalChannel = channelCount;
            outSampleCountsPtr = Module._malloc( totalChannel * Module.HEAP32.BYTES_PER_ELEMENT);
            outSampleCountsPtrStart = outSampleCountsPtr / Module.HEAP32.BYTES_PER_ELEMENT;
            outSampleCountsBuffer = Module.HEAP32.subarray(outSampleCountsPtrStart, (outSampleCountsPtrStart + totalChannel));

            for (let i = 0; i < totalChannel; i++) {
                outSampleCountsBuffer[i] = data.length;
            }
            inDataArr.set(data);
            // console.log("inDataArr:::: ", inDataArr.subarray(0,5));
            const deviceType = eventFromMain.data.deviceType;
            const serialResult = Module._processing_process_sample_stream(
                inSamplesPtr,
                outSampleCountsPtr,
                inDataPtr,
                data.length,
                deviceType
            );
            // console.log("SERIAL RESULT: ", serialResult);

            if (serialResult > 0) {
                postMessage({
                    "message": "SERIAL_DATA_TRANSFER",
                    "frameCount": serialResult,
                });
            }


            // console.log("serialResult: ", totalChannel, serialResult, outSampleCountsBuffer, inSamplesBuffer );
            // for (let i = 0; i < totalChannel; i++) {
            //     const slicedArray = inSamplesBuffer.subarray(0, outSampleCountsBuffer[i]).slice();
            //     const data = {
            //         "message": "INPUT_SERIAL_BUFFER_FINISHED",
            //         "channelIdx": i,
            //         "bufferViews": slicedArray,
            //     };
            //     // console.log("data : ", totalChannel, idx);
            //     // console.log(slicedArray);
            //     postMessage(data);
            // }

            Module._free(inSamplesPtr);
            Module._free(inDataPtr);
            Module._free(outSampleCountsPtr);

            // return;

            // console.log("serialResult: ", totalChannel, serialResult, outSampleCountsBuffer, outSamplesBuffer );
            if (serialResult != 0) {
            }
        




            // if (eventFromMain.data.toApplyHighPass) {

            //     const response = Module.ccall(
            //         'applyHighPassFilter',
            //         'number', // Assuming the function returns a number (pointer)
            //         ['number', 'number', 'number'], // Argument types: int16_t, short*, int32_t
            //         [eventFromMain.data.channelIdx, ptrDataArrayChannelWise[eventFromMain.data.channelIdx], eventFromMain.data.sampleCount]
            //     );
            //     // console.log("buffer error check");
            // }
            // if (eventFromMain.data.toApplyLowPass) {
            //     const response = Module.ccall(
            //         'applyLowPassFilter',
            //         'number', // Assuming the function returns a number (pointer)
            //         ['number', 'number', 'number'], // Argument types: int16_t, short*, int32_t
            //         [eventFromMain.data.channelIdx, ptrDataArrayChannelWise[eventFromMain.data.channelIdx], eventFromMain.data.sampleCount]
            //     );
            // }

            // postMessage({
            //     message: "onWebApplyFilter",
            //     channelIdx: eventFromMain.data.channelIdx,
            // });
        break;
        case "DISPLAY_SERIAL_DATA_WEB":
            try {
                startPositionIdx = eventFromMain.data.startPositionIdx;
                endPositionIdx = eventFromMain.data.endPositionIdx;

                totalChannel = channelCount;
                // _displayTimeMs = eventFromMain.data.displayTimeMs;
                drawSurfaceWidth = eventFromMain.data.drawSurfaceWidth;
                eventLabels = JSON.parse(eventFromMain.data.eventLabels);
                eventPositions = JSON.parse(eventFromMain.data.eventPositions);
                // eventLabels = [];
                // eventPositions = [];

                // console.log("startPositionIdx: ", startPositionIdx, endPositionIdx);

                const startPosMultiplier = drawSurfaceWidth * 5;
                outSamplesPtr = Module._malloc(drawSurfaceWidth * 5 * totalChannel * Module.HEAP16.BYTES_PER_ELEMENT);
                outSamplesPtrStart = outSamplesPtr / Module.HEAP16.BYTES_PER_ELEMENT;
                outSamplesBuffer = Module.HEAP16.subarray(outSamplesPtrStart, (outSamplesPtrStart + drawSurfaceWidth * 5 * totalChannel));
    
                outSampleCountsDrawingPtr = Module._malloc( totalChannel * Module.HEAP32.BYTES_PER_ELEMENT);
                outSampleCountsDrawingPtrStart = outSampleCountsDrawingPtr / Module.HEAP32.BYTES_PER_ELEMENT;
                outSampleCountsDrawingBuffer = Module.HEAP32.subarray(outSampleCountsDrawingPtrStart, (outSampleCountsDrawingPtrStart + totalChannel));
    
                totalEvents = eventLabels.length;
                outEventIndicesPtr = Module._malloc( totalEvents * Module.HEAPF32.BYTES_PER_ELEMENT);
                outEventIndicesPtrStart = outEventIndicesPtr / Module.HEAPF32.BYTES_PER_ELEMENT;
                outEventIndicesBuffer = Module.HEAPF32.subarray(outEventIndicesPtrStart, (outEventIndicesPtrStart + totalEvents));
    
                totalEventCounts = 1;
                outEventCountPtr = Module._malloc( totalEvents * Module.HEAP32.BYTES_PER_ELEMENT);
                outEventCountPtrStart = outEventCountPtr / Module.HEAP32.BYTES_PER_ELEMENT;
                outEventCountBuffer = Module.HEAP32.subarray(outEventCountPtrStart, (outEventCountPtrStart + totalEventCounts));
    
                inTotalEvents = eventLabels.length;
                inEventIndicesPtr = Module._malloc( inTotalEvents * Module.HEAP32.BYTES_PER_ELEMENT);
                inEventIndicesPtrStart = inEventIndicesPtr / Module.HEAP32.BYTES_PER_ELEMENT;
                inEventIndicesBuffer = Module.HEAP32.subarray(inEventIndicesPtrStart, (inEventIndicesPtrStart + inTotalEvents));
                displayTimeMs = _displayTimeMs;
                try{
                    if (inTotalEvents > 0) {
                        inEventIndicesBuffer.set(eventPositions);
                    }
                    // inEventIndicesBuffer.set([100]);
                    // console.log("eventLabels: ", eventPositions);
                }catch(err) {
                    console.log("ERR111", eventPositions, inEventIndicesBuffer);
                }
                for (let i = 0; i < totalChannel; i++) {
                    outSampleCountsDrawingBuffer[i] = startPosMultiplier;
                }
                  
                // console.log("SERIAL DRAWING: ", (displayTimeMs * 0.001 * sampleRate));
                let resultDrawing = Module._processing_prepare_for_signal_drawing(
                    outSamplesPtr,           // Pointer<Pointer<Float>>
                    // currentDataBuffersPtr,           // Pointer<Pointer<Float>>
                    outSampleCountsDrawingPtr,      // Pointer<Int32>
                    outEventIndicesPtr,      // Pointer<Float>
                    outEventCountPtr,        // Pointer<Int32>
                    inEventIndicesPtr,       // Pointer<Int32>
                    totalEvents,                       // int (inEventCount)
                    // 0,                       // int (fromSample)
                    // Math.floor(displayTimeMs * 0.001 * sampleRate),  // int (toSample)
                    startPositionIdx,                       // int (fromSample)
                    endPositionIdx,  // int (toSample)
                    // 500,  // int (toSample)
                    drawSurfaceWidth         // int
                );

                // console.log("resultDrawing: ", resultDrawing, outSamplesBuffer);
                if (resultDrawing == 0) {
                    if (inTotalEvents > 0) {
                        console.log("outEventIndicesBuffer: ", outEventIndicesBuffer.subarray(0, inTotalEvents), inEventIndicesBuffer, eventPositions);
                        outEventPositionBuffer.set(outEventIndicesBuffer.subarray(0, inTotalEvents));
                    }

                    for (let i = 0; i < channelCount; i++) {
                        const outSampleCount = outSampleCountsDrawingBuffer[i];
                        const slicedArray = outSamplesBuffer.slice( i * startPosMultiplier, i * startPosMultiplier + outSampleCount);
                        drawingDataBufferList[i].set(slicedArray);
                        drawingCountBufferList[i] = outSampleCount;
                    }

                    const data = {
                        "message": "INPUT_SERIAL_BUFFER_FINISHED",
                        "channelIdx": 0,
                        "bufferViews": drawingDataBufferList,
                        "bufferCountViews": drawingCountBufferList,
                    };

                    postMessage(data);

                }

                // Module._free(outSignalPtr);
                Module._free(outSamplesPtr);
                Module._free(outSampleCountsDrawingPtr);
                Module._free(outEventIndicesPtr);
                Module._free(outEventCountPtr);
                Module._free(inEventIndicesPtr);
            }catch(err){
                console.log("err");
                console.log(err);
            } finally {
            }

        break;

        default:
    }
}

if ('function' === typeof importScripts) {
    self.importScripts("cprocessing.js");
    self.Module.onRuntimeInitialized = async _ => {
        console.log("ccall : ", self.Module.ccall );
        postMessage({
            message: 'INITIALIZE_WASM',
        });
    };
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}


function setExpansionBoardType(rawPosExpBoardType){
    
    posExpBoardType = rawPosExpBoardType >> 1;
    const expBoardTypeBuffer = HEAP16.subarray(posExpBoardType, posExpBoardType + 1);
    if (previousExpBoardType != expBoardTypeBuffer[0]) {
        previousExpBoardType = expBoardTypeBuffer[0];
        postMessage({
            "message": "SET_EXPANSION_BOARD_TYPE",
            "expansionBoardType": expBoardTypeBuffer[0],
        });
        console.log("setExpansionBoardType : ", previousExpBoardType, expBoardTypeBuffer[0]);
    }
}

let previousExpBoardType = -1;
// setInterval(() => {
//     // var posExpBoardType = expBoardTypePtr;
//     // const expBoardTypeBuffer = HEAP32.subarray(posExpBoardType, posExpBoardType + 1);
//     if (expBoardTypeBuffer !== undefined && expBoardTypeBuffer.length> 0 && previousExpBoardType != expBoardTypeBuffer[0]) {
//         previousExpBoardType = expBoardTypeBuffer[0];
//         console.log("posExpBoardType: ", expBoardTypePtr, expBoardTypeBuffer);
//         postMessage({
//             "message": "SET_EXPANSION_BOARD_TYPE",
//             "expansionBoardType": expBoardTypeBuffer[0],
//         });
//     }

// }, 2000);




function convertFloat32ToFloat64(float32Array, oriArr) {
  const float64Array = new Float64Array(float32Array.length);
  for (let i = 0; i < float32Array.length; i++) {
    if (float32Array[i] < 1) {
        float64Array[i] = oriArr[i]; // automatic widening
    } else {
        float64Array[i] = float32Array[i]; // automatic widening
    }
  }
  return float64Array;
}