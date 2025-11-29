let isOpeningFile = false;

let osFilePath = "";
let isRecording = -1;
let recordingFileHandle;
let recordingFileWritable;
let workerChannelPort;

let loadedSamplesBuffer;
let loadedSamplesCountBuffer;
let loadedConfigBuffer;
// NWB Plugin module (modularized)
let NwbModule;

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

/* THRESHOLDING
*/

let isThresholding = false;
let thresholdArrayLength = 0;

/* FFT */
let out_window_countPtr;
let out_window_count;
let out_window_sizePtr;
let out_window_size;
let out_frequency_counter;

let out_fft_data;
let out_fft_data_2d;
let out_fft_vertices;
let out_fft_indices;
let out_fft_colors;
let out_fft_vertex_count;
let out_fft_index_count;
let out_fft_color_count;

let out_fft_dataPtr;
let out_fft_verticesPtr;
let out_fft_indicesPtr;
let out_fft_colorsPtr;
let out_fft_vertex_countPtr;
let out_fft_index_countPtr;
let out_fft_color_countPtr;
let out_frequency_counterPtr;
let inSamplesFftPtr;
let inSampleCountsFftPtr;

var tempOnMessage = self.onmessage;
self.onmessage = async function (eventFromMain) {
    switch (eventFromMain.data.message) {
        case "INIT_FFT":
            let fftChannelCount = eventFromMain.data.channelCount;
            let windowCount = eventFromMain.data.windowCount;
            let windowSize = eventFromMain.data.windowSize;
            out_fft_dataPtr = Module._malloc(windowCount * windowSize * Module.HEAPF32.BYTES_PER_ELEMENT);
            let out_fft_dataStart = out_fft_dataPtr / Module.HEAPF32.BYTES_PER_ELEMENT;
            out_fft_data = Module.HEAPF32.subarray(out_fft_dataStart, (out_fft_dataStart + windowCount * windowSize));
            console.log("INIT FFT STARTED");

            out_fft_verticesPtr = Module._malloc(windowCount * windowSize * 2 * Module.HEAPF32.BYTES_PER_ELEMENT);
            let out_fft_verticesStart = out_fft_verticesPtr / Module.HEAPF32.BYTES_PER_ELEMENT;
            out_fft_vertices = Module.HEAPF32.subarray(out_fft_verticesStart, (out_fft_verticesStart + windowCount * windowSize * 2));

            out_fft_indicesPtr = Module._malloc(windowCount * windowSize * 6 * Module.HEAP16.BYTES_PER_ELEMENT);
            let out_fft_indicesStart = out_fft_indicesPtr / Module.HEAP16.BYTES_PER_ELEMENT;
            out_fft_indices = Module.HEAP16.subarray(out_fft_indicesStart, (out_fft_indicesStart + windowCount * windowSize * 6));

            out_fft_colorsPtr = Module._malloc(windowCount * windowSize * 4 * Module.HEAPF32.BYTES_PER_ELEMENT);
            let out_fft_colorsStart = out_fft_colorsPtr / Module.HEAPF32.BYTES_PER_ELEMENT;
            out_fft_colors = Module.HEAPF32.subarray(out_fft_colorsStart, (out_fft_colorsStart + windowCount * windowSize * 4));

            out_fft_vertex_countPtr = Module._malloc(fftChannelCount * Module.HEAP32.BYTES_PER_ELEMENT);
            let out_fft_vertex_countStart = out_fft_vertex_countPtr / Module.HEAP32.BYTES_PER_ELEMENT;
            out_fft_vertex_count = Module.HEAP32.subarray(out_fft_vertex_countStart, (out_fft_vertex_countStart + fftChannelCount));

            out_fft_index_countPtr = Module._malloc(fftChannelCount * Module.HEAP32.BYTES_PER_ELEMENT);
            let out_fft_index_countStart = out_fft_index_countPtr / Module.HEAP32.BYTES_PER_ELEMENT;
            out_fft_index_count = Module.HEAP32.subarray(out_fft_index_countStart, (out_fft_index_countStart + fftChannelCount));

            out_fft_color_countPtr = Module._malloc(fftChannelCount * Module.HEAP32.BYTES_PER_ELEMENT);
            let out_fft_color_countStart = out_fft_color_countPtr / Module.HEAP32.BYTES_PER_ELEMENT;
            out_fft_color_count = Module.HEAP32.subarray(out_fft_color_countStart, (out_fft_color_countStart + fftChannelCount));

            out_window_countPtr = Module._malloc(fftChannelCount * Module.HEAP32.BYTES_PER_ELEMENT);
            let out_window_countStart = out_window_countPtr / Module.HEAP32.BYTES_PER_ELEMENT;
            out_window_count = Module.HEAP32.subarray(out_window_countStart, (out_window_countStart + fftChannelCount));

            out_window_sizePtr = Module._malloc(fftChannelCount * Module.HEAP32.BYTES_PER_ELEMENT);
            let out_window_sizeStart = out_window_sizePtr / Module.HEAP32.BYTES_PER_ELEMENT;
            out_window_size = Module.HEAP32.subarray(out_window_sizeStart, (out_window_sizeStart + fftChannelCount));
            
            out_frequency_counterPtr = Module._malloc(fftChannelCount * Module.HEAP32.BYTES_PER_ELEMENT);
            let out_frequency_counterStart = out_frequency_counterPtr / Module.HEAP32.BYTES_PER_ELEMENT;
            out_frequency_counter = Module.HEAP32.subarray(out_frequency_counterStart, (out_frequency_counterStart + fftChannelCount));

            console.log("INIT FFT FINISHED");

            // inSamplesFftPtr = Module._malloc(fftChannelCount * Module.HEAP16.BYTES_PER_ELEMENT * sampleLength);
            // let inSamplesFftStart = inSamplesFftPtr / Module.HEAP16.BYTES_PER_ELEMENT;
            // let in_samples_fft = Module.HEAP16.subarray(inSamplesFftStart, (inSamplesFftStart + sampleLength));

            // inSampleCountsFftPtr = Module._malloc(fftChannelCount * Module.HEAP16.BYTES_PER_ELEMENT);
            // let inSampleCountsFftStart = inSampleCountsFftPtr / Module.HEAP16.BYTES_PER_ELEMENT;
            // let in_sample_counts_fft = Module.HEAP16.subarray(inSampleCountsFftStart, (inSampleCountsFftStart + fftChannelCount));
// List<Float32List> out_fft_data, Int16List out_window_count, Int16List out_window_size, Int16List out_frequency_counter, Int16List inSamples, Int16List inSampleCounts,
// Float32List out_fft_vertices, Int16List out_fft_indices, Float32List out_fft_colors, Int16List out_fft_vertex_count, Int16List out_fft_index_count, Int16List out_fft_color_count 
            out_fft_data_2d = [];
            for (let i = 0; i < windowCount; i++) {
                out_fft_data_2d.push(out_fft_data.subarray(i * windowSize, (i + 1) * windowSize));
            }
            const fftData = {
                "message": "INIT_FFT_BUFFER_FINISHED",
                "out_fft_data": out_fft_data_2d,
                "out_window_count": out_window_count,
                "out_window_size": out_window_size,
                "out_frequency_counter": out_frequency_counter,
                // "in_samples_fft": in_samples_fft,
                // "in_sample_counts_fft": in_sample_counts_fft,
                "out_fft_vertices": out_fft_vertices,
                "out_fft_indices": out_fft_indices,
                "out_fft_colors": out_fft_colors,
                "out_fft_vertex_count": out_fft_vertex_count,
                "out_fft_index_count": out_fft_index_count,
                "out_fft_color_count": out_fft_color_count,
                "out_frequency_counter": out_frequency_counter,
            };
           
            postMessage(fftData);
            // List<Float32List> out_fft_data, Int16List out_window_count, Int16List out_window_size, Int16List out_frequency_counter, Int16List inSamples, Int16List inSampleCounts,
            // Float32List out_fft_vertices, Int16List out_fft_indices, Float32List out_fft_colors, Int16List out_fft_vertex_count, Int16List out_fft_index_count, Int16List out_fft_color_count 
                    
        break;
        case "INITIALIZE_MICROPHONE":
            console.log("Module" , Module, Module._processing_process_threshold);
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
        case "PROCESS_FFT_MICROPHONE_DATA":
            // channelCount = eventFromMain.data.channelCount;
            // let selectedChannel = eventFromMain.data.selectedChannel;
            // let windowCountFft = eventFromMain.data.windowCount["o"];
            // let windowSizeFft = eventFromMain.data.windowSize["o"];
            // let inSamples = eventFromMain.data.inSamples["o"];
            // let inSampleCounts = eventFromMain.data.inSampleCounts["o"];
            
            // processFftMicrophoneData(channelCount, selectedChannel, windowCountFft, windowSizeFft, inSamples, inSampleCounts);

        break;
        case "INIT_WITH_CONFIG":
            let initConfig = eventFromMain.data.config;
            console.log("INIT_WITH_CONFIG: ", initConfig);
            Module._processing_init();
            Module._processing_set_sample_rate(initConfig[0]);
            Module._processing_set_channel_count(initConfig[1]);
        break;
        // case "FILL_LOADED_SAMPLES_TO_BUFFER":
        //     let fillLoadedSamplesToBufferConfig = eventFromMain.data.config;
        //     console.log("FILL_LOADED_SAMPLES_TO_BUFFER: ", fillLoadedSamplesToBufferConfig);
        //     let isSerialDevice = loadedConfigBuffer[6];
        //     if (isSerialDevice == 1) {
                
        //     } else {
                
        //     }
        // break;
        case "PROCESS_PREPARE_FFT_DRAWING":
            let drawBufferFft = eventFromMain.data.drawBuffer["o"];
            let selectedChannelIdx = eventFromMain.data.selectedChannelIdx;
            let windowCountDrawFft = eventFromMain.data.windowCount;
            let windowSizeDrawFft = eventFromMain.data.windowSize;
            let targetWindowCountFft = eventFromMain.data.targetWindowCount;
            let widthFft = eventFromMain.data.width;
            let heightFft = eventFromMain.data.height;

            let drawBufferFftPtr = Module._malloc(windowCountDrawFft * windowSizeDrawFft * Module.HEAPF32.BYTES_PER_ELEMENT);
            let drawBufferFftPtrStart = drawBufferFftPtr / Module.HEAPF32.BYTES_PER_ELEMENT;
            let drawBufferFftBuffer = Module.HEAPF32.subarray(drawBufferFftPtrStart, (drawBufferFftPtrStart + windowCountDrawFft * windowSizeDrawFft));
            for (let i = 0; i < windowCountDrawFft; i++) {
                try {
                    let temp = drawBufferFftBuffer.subarray(i * windowSizeDrawFft, (i + 1) * windowSizeDrawFft);
                    temp.set(drawBufferFft[i]);
    
                } catch(err) {
                    console.log("err: ", err);
                }
            }

            let resultDrawingFft = Module._processing_prepare_fft_for_drawing(out_fft_verticesPtr, out_fft_indicesPtr, out_fft_colorsPtr, 
                out_fft_vertex_countPtr, out_fft_index_countPtr, out_fft_color_countPtr, 
                drawBufferFftPtr, windowCountDrawFft, windowSizeDrawFft, targetWindowCountFft, widthFft, heightFft);

            // console.log("WIDTH HEIGHT: ", widthFft, heightFft, "resultDrawingFft: ", resultDrawingFft);

            // console.log("out_fft_vertices: ", out_fft_vertices);
            postMessage({
                "message": "PROCESS_PREPARE_FFT_DRAWING_FINISHED",
                "resultFft": resultDrawingFft,
                "selectedChannelIdx": selectedChannelIdx,   
            });
            Module._free(drawBufferFftPtr);
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
            
            const samplesLen = drawSurfaceWidth * 20;
            outSamplesPtr = Module._malloc(samplesLen * totalChannel * Module.HEAP16.BYTES_PER_ELEMENT);
            outSamplesPtrStart = outSamplesPtr / Module.HEAP16.BYTES_PER_ELEMENT;
            outSamplesBuffer = Module.HEAP16.subarray(outSamplesPtrStart, (outSamplesPtrStart + samplesLen * totalChannel));

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

            outSampleCountsDrawingBuffer[0] = samplesLen;
            try {
                if (isThresholding) {
                    endPositionIdx = endPositionIdx == 0 ? 1 : endPositionIdx;
                    // startPositionIdx = 0;
                    // console.log("CHECK THRESHOLDING::: ", startPositionIdx, "===", endPositionIdx, thresholdArrayLength);
                }
              
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

                if (resultDrawing == 0) {
                    if (inTotalEvents > 0) {
                        outEventPositionBuffer.set(outEventIndicesBuffer.subarray(0, inTotalEvents));
                    }
                    try{
                        // console.log("outSampleCountsDrawingBuffer: " , outSampleCountsDrawingBuffer);
                        for (let i = 0; i < channelCount; i++) {
                            const outSampleCount = outSampleCountsDrawingBuffer[i];
                            const slicedArray = outSamplesBuffer.subarray( i * outSampleCount, (i + 1) * outSampleCount).slice();
                            const slicedCountArray = outSampleCountsBuffer.subarray(i, i + 1).slice();
                            // console.log("drawingCountBufferList: ", slicedCountArray[0], slicedArray.length);
                            drawingDataBufferList[i].set(slicedArray, 0);
                            drawingCountBufferList[i] = slicedArray.length;
                        }
                        // console.log("drawingDataBufferList: ", drawingDataBufferList[0].subarray(0,10));
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
            console.log("inDataArr: ", inDataArr.subarray(0,10));

            const micResult = Module._processing_process_microphone_stream(
                inSamplesPtr,
                outSampleCountsPtr,
                inDataPtr,
                data.length
            );
            
            let selectedChannel = 0;

            let FFT_30HZ_LENGTH = 32;
            let FFT_WINDOW_TIME_LENGTH = 4;          
            let windowCountFft = Math.floor( (10.0 * 128) / Math.floor(512 * 0.01) );
            let windowSizeFft = (FFT_30HZ_LENGTH * FFT_WINDOW_TIME_LENGTH);
      
            processFftMicrophoneData(channelCount, selectedChannel, windowCountFft, windowSizeFft, [inSamplesBuffer], outSampleCountsBuffer);

            if (isRecording == 0) {
                let samplesLength = outSampleCountsBuffer[0];
                let channelsLength = 1;

                let samplesPtr = NwbModule._malloc(samplesLength * Module.HEAP16.BYTES_PER_ELEMENT);
                let samplesPtrStart = samplesPtr / Module.HEAP16.BYTES_PER_ELEMENT;
                let samplesBuffer = NwbModule.HEAP16.subarray(samplesPtrStart, (samplesPtrStart + samplesLength));
                samplesBuffer.set(inSamplesBuffer.subarray(0, samplesLength));
                
                let samplesCtrPtr = NwbModule._malloc(channelsLength * Module.HEAP32.BYTES_PER_ELEMENT);
                let samplesCtrPtrStart = samplesCtrPtr / Module.HEAP32.BYTES_PER_ELEMENT;
                let samplesCtrBuffer = NwbModule.HEAP32.subarray(samplesCtrPtrStart, (samplesCtrPtrStart + channelsLength));
                samplesCtrBuffer[0] = samplesLength;

                // console.log("samplesLength: ", samplesLength, "channelsLength: ", channelsLength, "samplesCtrBuffer: ", samplesCtrBuffer);
                NwbModule._nwbfile_add_electrical_series(samplesPtr, samplesCtrPtr, 0, 1, isRecording);
            }

            if (isThresholding) {
            
                let outThresholdSamplesPtr = Module._malloc( packetLen * Module.HEAP16.BYTES_PER_ELEMENT);
                // let outThresholdSamplesPtrStart = outThresholdSamplesPtr / Module.HEAP16.BYTES_PER_ELEMENT;
                // let outThresholdSamplesBuffer = Module.HEAP16.subarray(outThresholdSamplesPtrStart, (outThresholdSamplesPtrStart + packetLen));

                let outThresholdSampleCountsPtr = Module._malloc( totalChannel * Module.HEAP32.BYTES_PER_ELEMENT);
                let outThresholdSampleCountsPtrStart = outThresholdSampleCountsPtr / Module.HEAP32.BYTES_PER_ELEMENT;
                let outThresholdSampleCountsBuffer = Module.HEAP32.subarray(outThresholdSampleCountsPtrStart, (outThresholdSampleCountsPtrStart + totalChannel));

                let eventLabels = JSON.parse(eventFromMain.data.eventLabels);
                let eventPositions = JSON.parse(eventFromMain.data.eventPositions);

                let inEventIndicesPtr = Module._malloc( eventLabels.length * Module.HEAP32.BYTES_PER_ELEMENT);
                let inEventIndicesPtrStart = inEventIndicesPtr / Module.HEAP32.BYTES_PER_ELEMENT;
                let inEventIndicesBuffer = Module.HEAP32.subarray(inEventIndicesPtrStart, (inEventIndicesPtrStart + eventLabels.length));
                for (let i = 0; i < eventLabels.length; i++) {
                    inEventIndicesBuffer[i] = MAX_DISPLAY_SECONDS * sampleRate - eventPositions[i] - 512;
                }

                let inEventLabelsPtr = Module._malloc( eventLabels.length * Module.HEAP32.BYTES_PER_ELEMENT);
                let inEventLabelsPtrStart = inEventLabelsPtr / Module.HEAP32.BYTES_PER_ELEMENT;
                let inEventLabelsBuffer = Module.HEAP32.subarray(inEventLabelsPtrStart, (inEventLabelsPtrStart + eventLabels.length));
                inEventLabelsBuffer.set(eventLabels);
                // let outThresholdSampleCountsPtrStart = outThresholdSampleCountsPtr / Module.HEAP32.BYTES_PER_ELEMENT;
                // let outThresholdSampleCountsBuffer = Module.HEAP32.subarray(outThresholdSampleCountsPtrStart, (outThresholdSampleCountsPtrStart + totalChannel));



                let thresholdResult = Module._processing_process_threshold(
                    outThresholdSamplesPtr, outThresholdSampleCountsPtr, 
                    inSamplesPtr, outSampleCountsPtr,
                    inEventIndicesPtr, inEventLabelsPtr, eventLabels.length,
                    true
                );
                
// int32_t processing_process_threshold(int16_t* _out_samples, int32_t* out_sample_counts,
//                                     int16_t* _in_samples,  int32_t* in_sample_counts,
//                                     const int32_t* in_event_indices, const int32_t* in_event_labels, int32_t in_event_count,
//                                    bool average_samples) {

                if (thresholdResult == 0) {
                    // push to note the current array length
                    thresholdArrayLength = outThresholdSampleCountsBuffer[0];
                    // if (thresholdArrayLength == 0) {
                        // console.log("thresholdArrayLength: ", thresholdArrayLength);
                    // }
                    const data = {
                        "message": "THRESHOLD_PROCESSED_ARRAY_LENGTH",
                        "thresholdArrayLength": outThresholdSampleCountsBuffer[0],
                    };

                    postMessage(data);

                }

                Module._free(outThresholdSamplesPtr);
                Module._free(outThresholdSampleCountsPtr);
                Module._free(inEventIndicesPtr);
                Module._free(inEventLabelsPtr);

            }
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

            Module._initHighPassFilter(channelCount, sampleRate, cutOffFrequency, q);
            break;

        case "webInitLowPassFilter":
            channelCount = eventFromMain.data.channelCount;
            sampleRate = eventFromMain.data.sampleRate;
            cutOffFrequency = eventFromMain.data.cutOffFrequency;
            q = eventFromMain.data.q;
            Module._initLowPassFilter(channelCount, sampleRate, cutOffFrequency, q);
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

            channelIdx = eventFromMain.data.channelIdx;

            inDataPtr = Module._malloc(data.length * Module.HEAPU8.BYTES_PER_ELEMENT);
            inDataPtrStart = inDataPtr / Module.HEAPU8.BYTES_PER_ELEMENT;
            inDataArr = Module.HEAPU8.subarray(inDataPtrStart, (inDataPtrStart + data.length));
            
            drawSurfaceWidth = eventFromMain.data.drawSurfaceWidth;
            const serialPacketLen = drawSurfaceWidth * 5;
            // const serialPacketLen = data.length;
            // const serialPacketLen = MAX_DISPLAY_SECONDS * sampleRate;
            inSamplesPtr = Module._malloc( serialPacketLen * totalChannel * Module.HEAP16.BYTES_PER_ELEMENT);
            inSamplesPtrStart = inSamplesPtr / Module.HEAP16.BYTES_PER_ELEMENT;
            inSamplesBuffer = Module.HEAP16.subarray(inSamplesPtrStart, (inSamplesPtrStart + serialPacketLen * totalChannel));
            // inSamplesBuffer.fill(0, 0, serialPacketLen * totalChannel);

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
            // console.log("isThresholding: ", isThresholding);

            if (serialResult > 0) {
                // console.log("SERIAL RESULT: ", serialResult, inSamplesBuffer, outSampleCountsBuffer);
                if (isThresholding) {
                    let eventLabels = JSON.parse(eventFromMain.data.eventLabels);
                    let eventPositions = JSON.parse(eventFromMain.data.eventPositions);
                    // if we set 525 it trigger the threshold. Why the value from sampleStream processor is big?
                    // inSamplesBuffer.fill(525, 0, outSampleCountsBuffer[0] + outSampleCountsBuffer[1]);


                    let serialPacketLenThreshold = serialPacketLen * 20;
                    // let serialPacketLenThreshold = 12000;
                    let outThresholdSamplesPtr = Module._malloc( serialPacketLenThreshold * totalChannel * Module.HEAP16.BYTES_PER_ELEMENT);
                    let outThresholdSamplesPtrStart = outThresholdSamplesPtr / Module.HEAP16.BYTES_PER_ELEMENT;
                    let outThresholdSamplesPtrBuffer = Module.HEAP16.subarray(outThresholdSamplesPtrStart, (outThresholdSamplesPtrStart + serialPacketLenThreshold *totalChannel));
                    
                    let outThresholdSampleCountsPtr = Module._malloc( totalChannel * Module.HEAP32.BYTES_PER_ELEMENT);
                    let outThresholdSampleCountsPtrStart = outThresholdSampleCountsPtr / Module.HEAP32.BYTES_PER_ELEMENT;
                    let outThresholdSampleCountsBuffer = Module.HEAP32.subarray(outThresholdSampleCountsPtrStart, (outThresholdSampleCountsPtrStart + totalChannel));
                    outThresholdSampleCountsBuffer.fill(serialPacketLenThreshold, 0, totalChannel);


                    let inEventIndicesPtr = Module._malloc( eventLabels.length * Module.HEAP32.BYTES_PER_ELEMENT);
                    let inEventIndicesPtrStart = inEventIndicesPtr / Module.HEAP32.BYTES_PER_ELEMENT;
                    let inEventIndicesBuffer = Module.HEAP32.subarray(inEventIndicesPtrStart, (inEventIndicesPtrStart + eventLabels.length));
                    for (let i = 0; i < eventLabels.length; i++) {
                        inEventIndicesBuffer[i] = MAX_DISPLAY_SECONDS * sampleRate - eventPositions[i] - serialResult;
                    }

                    let inEventLabelsPtr = Module._malloc( eventLabels.length * Module.HEAP32.BYTES_PER_ELEMENT);
                    let inEventLabelsPtrStart = inEventLabelsPtr / Module.HEAP32.BYTES_PER_ELEMENT;
                    let inEventLabelsBuffer = Module.HEAP32.subarray(inEventLabelsPtrStart, (inEventLabelsPtrStart + eventLabels.length));
                    inEventLabelsBuffer.set(eventLabels);

                    // inSamplesBuffer.fill(100, 0, serialPacketLen * totalChannel);


                    let thresholdResult = Module._processing_process_threshold(
                        outThresholdSamplesPtr, outThresholdSampleCountsPtr, 
                        inSamplesPtr, outSampleCountsPtr,
                        inEventIndicesPtr, inEventLabelsPtr, eventLabels.length,
                        true
                    );
                    // console.log("outThresholdSamplesPtrBuffer: ", outThresholdSamplesPtrBuffer.subarray(0, 20));

                    if (thresholdResult == 0) {
                        // console.log("SERIAL RESULT: ", thresholdResult, inSamplesBuffer);
                        thresholdArrayLength = outThresholdSampleCountsBuffer[0];
                        const data = {
                            "message": "THRESHOLD_PROCESSED_ARRAY_LENGTH",
                            "thresholdArrayLength": outThresholdSampleCountsBuffer[0],
                        };
                        postMessage(data);
                    }

                    Module._free(outThresholdSamplesPtr);
                    Module._free(outThresholdSampleCountsPtr);
                    Module._free(inEventIndicesPtr);
                    Module._free(inEventLabelsPtr);

                }
                postMessage({
                    "message": "SERIAL_DATA_TRANSFER",
                    "frameCount": serialResult,
                });
                
            }

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
                // startPositionIdx = 0;
                // endPositionIdx = sampleRate * MAX_DISPLAY_SECONDS;
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
                outSamplesPtr = Module._malloc(startPosMultiplier * totalChannel * Module.HEAP16.BYTES_PER_ELEMENT);
                outSamplesPtrStart = outSamplesPtr / Module.HEAP16.BYTES_PER_ELEMENT;
                outSamplesBuffer = Module.HEAP16.subarray(outSamplesPtrStart, (outSamplesPtrStart + startPosMultiplier * totalChannel));
    
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
                    if (isThresholding) {
                        endPositionIdx = endPositionIdx == 0 ? 1 : endPositionIdx;
                    }

                    if (inTotalEvents > 0) {
                        inEventIndicesBuffer.set(eventPositions);
                    }
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

                // console.log("resultDrawing: ", resultDrawing, outSampleCountsDrawingBuffer);
                if (resultDrawing == 0) {
                    if (inTotalEvents > 0) {
                        // console.log("outEventIndicesBuffer: ", outEventIndicesBuffer.subarray(0, inTotalEvents), inEventIndicesBuffer, eventPositions);
                        outEventPositionBuffer.set(outEventIndicesBuffer.subarray(0, inTotalEvents));
                    }

                    for (let i = 0; i < channelCount; i++) {
                        const outSampleCount = outSampleCountsDrawingBuffer[i];

                        const slicedArray = outSamplesBuffer.slice( i * startPosMultiplier, i * startPosMultiplier + outSampleCount);
                        drawingDataBufferList[i].set(slicedArray);
                        drawingCountBufferList[i] = outSampleCount;
                        // if (isThresholding) {
                        //     console.log("outSampleCountsDrawingPtr: ", i, " channel:", totalChannel, " ==== ", slicedArray, outSamplesBuffer.length, startPosMultiplier);
                        // }
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
        case "INIT_THRESHOLD":
            let thresholdChannelCount = eventFromMain.data.channelCount;
            let thresholdSampleRate = eventFromMain.data.sampleRate;
            // let drawSurfaceWidth = eventFromMain.data.drawSurfaceWidth;
            Module._processing_init();
            Module._processing_set_channel_count(thresholdChannelCount);
            console.log("INIT THRESHOLDDDD: ", thresholdChannelCount, thresholdSampleRate);
            Module._processing_set_sample_rate(thresholdSampleRate);
        break;
        case "SET_THRESHOLD_AVERAGE_SAMPLE":
            let avgSampleCount = eventFromMain.data.avgSampleCount;
            Module._processing_set_averaged_sample_count(avgSampleCount);
        break;
        case "SET_THRESHOLD_VALUE":
            let thresholdValue = eventFromMain.data.thresholdValue;
            Module._processing_set_threshold(thresholdValue);
        break;
        case "SET_THRESHOLD_IS_THRESHOLDING":
            isThresholding = eventFromMain.data.isThresholding;
            Module._processing_set_is_thresholding(isThresholding);
        break;
        case "SET_THRESHOLD_TRIGGER_TYPE":
            let eventThresholdTriggeredType = eventFromMain.data.eventThresholdTriggeredType;
            Module._processing_set_averaging_trigger_type(eventThresholdTriggeredType);
        break;
        case "CREATE_NWB_FILE":
            if (!NwbModule) {
                console.error("NwbModule not initialized yet");
                return;
            }
                        
            isRecording = 0;
            let filePath = eventFromMain.data.filePath;
            osFilePath = filePath;

            let nwbSampleRate = eventFromMain.data.sampleRate;
            let nwbChannelCount = eventFromMain.data.channelCount;
            recordingFileHandle = eventFromMain.data.fileHandle;
            
            recordingFileWritable = await recordingFileHandle.createWritable();
            let deviceInfoPointer = eventFromMain.data.deviceInfoPointer;
            let deviceManufacturerPointer = eventFromMain.data.deviceManufacturerPointer;
            // NwbModule._processing_init(filePath, nwbSampleRate, nwbChannelCount, deviceInfoPointer, deviceManufacturerPointer);
            const result = NwbModule.ccall(
                'processing_init',
                'number',
                ['string', 'number', 'number', 'string', 'string'],
                [filePath, nwbSampleRate, nwbChannelCount, deviceInfoPointer, deviceManufacturerPointer]
            );            
            console.log("PROCESSING INIT result: ", result);
            postMessage({
                "message": "NWB_FILE_CREATED",
                "result": filePath,
            });
        break;
        case "ADD_ELECTRICAL_SERIES":
            if (!NwbModule) {
                console.error("NwbModule not initialized yet");
                return;
            }
            // addElectricalSeries(Int16List data, Int32List samplesCount, int selectedChannel,int channelCount, int isFinishRecording) {
            let samples = eventFromMain.data.samples;
            let samplesCount = eventFromMain.data.samplesCount;
            let nwbSelectedChannel = eventFromMain.data.selectedChannel;
            let tempNwbChannelCount = eventFromMain.data.channelCount;
            let isFinishRecording = eventFromMain.data.isFinishRecording;

            // console.log("samples: ", samples, samplesCount, nwbSelectedChannel, tempNwbChannelCount, isFinishRecording);
            if (isFinishRecording == 1){ // FINISH RECORDING
                // NwbModule._nwbfile_add_electrical_series(samples, samplesCount, nwbSelectedChannel, tempNwbChannelCount, isFinishRecording);
                let samplesPtr = NwbModule._malloc(1 * Module.HEAP16.BYTES_PER_ELEMENT);
                let samplesCtrPtr = NwbModule._malloc(1 * Module.HEAP32.BYTES_PER_ELEMENT);
                NwbModule._nwbfile_add_electrical_series(samplesPtr, samplesCtrPtr, nwbSelectedChannel, tempNwbChannelCount, isFinishRecording);

                isRecording = -1;
                makeFilePublicWeb(osFilePath);

            } else {
                isRecording = isFinishRecording;
                print("samples: ", samples.length, "samplesCount.length: ", samplesCount.length);
                let samplesPtr = NwbModule._malloc(samples.length * Module.HEAP16.BYTES_PER_ELEMENT);
                let samplesPtrStart = samplesPtr / Module.HEAP16.BYTES_PER_ELEMENT;
                let samplesBufferRecording = Module.HEAP16.subarray(samplesPtrStart, (samplesPtrStart + samples.length));
                samplesBufferRecording.set(samples);

                let samplesCtrPtr = NwbModule._malloc(samplesCount.length * Module.HEAP32.BYTES_PER_ELEMENT);
                let samplesCtrPtrStart = samplesCtrPtr / Module.HEAP32.BYTES_PER_ELEMENT;
                let samplesCtrBuffer = Module.HEAP32.subarray(samplesCtrPtrStart, (samplesCtrPtrStart + samplesCount.length));
                samplesCtrBuffer.set(samplesCount);
                
                NwbModule._nwbfile_add_electrical_series(samplesPtr, samplesCtrPtr, nwbSelectedChannel, tempNwbChannelCount, isFinishRecording);
                // postMessage({
                //     "message": "ELECTRICAL_SERIES_ADDED",
                // });    
            }
        break;
        case "MAKE_FILE_PUBLIC":
            makeFilePublicWeb(eventFromMain.data.filePath);
        break;
        
        case "START_OPENING_FILE_WEB":
            let fileName = eventFromMain.data.filePath;
            let startIdx = eventFromMain.data.startIdx;
            let endIdx = eventFromMain.data.endIdx;
            let startChannel = eventFromMain.data.startChannel;
            let endChannel = eventFromMain.data.endChannel;
            let fileHandle = eventFromMain.data.fileHandle;
            let isStartOpeningFileWeb = eventFromMain.data.isStartOpeningFileWeb;
            

            if (isStartOpeningFileWeb) {
                let FS = null;                
                if (NwbModule.FS) {
                    FS = NwbModule.FS;
                } else if (typeof FS !== 'undefined') {
                    // FS is global
                } else if (NwbModule._FS) {
                    FS = NwbModule._FS;
                }
                try{
                    const wasmfsFile = await FS.readFile(fileName);
                    console.log("FILE EXISTS", fileName)
                }catch(err){
                    console.log("err");
                    console.log(err);
                    const readData = await fileHandle.getFile();
                    if (readData) {
                        const fileBuffer = await readData.arrayBuffer();
                        const arrayBuffer = new Uint8Array(fileBuffer);
                        await FS.writeFile(fileName, arrayBuffer);
                        console.log("FILE WRITTER", fileName)
                    }
    
                }
            }

            // seek buffer       
            let samplesLength = endIdx - startIdx;
            let loadedChannelCount = endChannel - startChannel;
            let loadedOutSamples = NwbModule._malloc(samplesLength * NwbModule.HEAP16.BYTES_PER_ELEMENT);
            let loadedOutSamplesCount = NwbModule._malloc(loadedChannelCount * NwbModule.HEAP32.BYTES_PER_ELEMENT);
            let loadedOutConfig = NwbModule._malloc(10 * NwbModule.HEAP32.BYTES_PER_ELEMENT);

            seekNwbFileBufferWeb(fileName, loadedOutSamples, loadedOutSamplesCount, loadedOutConfig, startIdx, endIdx, startChannel, endChannel, samplesLength, isStartOpeningFileWeb);
        break;
        default:
    }
}

if ('function' === typeof importScripts) {
    // Import both scripts
    self.importScripts("cprocessing.js", "nwbfile_plugin.js");
    
    // cprocessing.js (no modularize) - automatically sets up self.Module
    self.Module.onRuntimeInitialized = async _ => {
        console.log("cprocessing Module initialized, ccall: ", self.Module.ccall);
        
        // Initialize NWB Plugin (modularize=1) - NWBPlugin is a factory function
        try {
            NwbModule = await NWBPlugin();
            console.log("NwbModule: ", NwbModule);
            self.NwbModule = NwbModule;
            console.log("NWB Plugin Module initialized: ", NwbModule);
            
            // Both modules are now ready
            postMessage({
                message: 'INITIALIZE_WASM',
            });
        } catch (error) {
            console.error("Failed to initialize NWB Plugin:", error);
        }
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


function processFftMicrophoneData(channelCount, selectedChannel, windowCountFft, windowSizeFft, inSamples, inSampleCounts) {
    let totalSampleLength = 0;
    for (let i = 0; i < channelCount; i++) {
        totalSampleLength += inSamples[i].length;
    }
    let inSamplesFftPtr = Module._malloc(totalSampleLength * Module.HEAP16.BYTES_PER_ELEMENT );
    let inSamplesFftPtrStart = inSamplesFftPtr / Module.HEAP16.BYTES_PER_ELEMENT;
    let inSamplesFftBuffer = Module.HEAP16.subarray(inSamplesFftPtrStart, (inSamplesFftPtrStart + totalSampleLength));
    
    let inSampleCountsFftPtr = Module._malloc(channelCount * Module.HEAP32.BYTES_PER_ELEMENT);
    let inSampleCountsFftPtrStart = inSampleCountsFftPtr / Module.HEAP32.BYTES_PER_ELEMENT;
    let inSampleCountsFftBuffer = Module.HEAP32.subarray(inSampleCountsFftPtrStart, (inSampleCountsFftPtrStart + channelCount));


    // Set window count and size arrays
    let outWindowCountArray = out_window_count;
    outWindowCountArray[selectedChannel] = windowCountFft;

    let outWindowSizeArray = out_window_size;
    outWindowSizeArray[selectedChannel] = windowSizeFft;

    // console.log("FFT PARAMS: windowCount:", windowCountFft, "windowSize:", windowSizeFft, "totalSampleLength:", totalSampleLength);

    // Copy samples sequentially, not at i * sampleLength intervals
    let currentOffset = 0;
    for (let i = 0; i < channelCount; i++) {
        inSamplesFftBuffer.set(inSamples[i], currentOffset);
        inSampleCountsFftBuffer[i] = inSamples[i].length;
        currentOffset += inSamples[i].length;
    }
    // EXTERNC FUNCTION_ATTRIBUTE int32_t processing_process_fft(float* _out_fft, int32_t* out_window_count,
        // int32_t* out_window_size, int16_t* _in_samples,
        // const int32_t* in_sample_counts) {

    let resultFft = Module._processing_process_fft(out_fft_dataPtr, out_window_countPtr, out_window_sizePtr, inSamplesFftPtr, inSampleCountsFftPtr);

    // Module._free(outWindowCountRaw);
    // Module._free(outWindowSizeRaw);

    postMessage({
        "message": "PROCESS_FFT_MICROPHONE_DATA_FINISHED",
        "resultFft": resultFft,
        "out_window_count": out_window_count, 
        "out_window_size": out_window_size, 
        "out_fft_data": out_fft_data_2d, 
        "selectedChannel": selectedChannel,
        "channelCounts": channelCount                
    });

    Module._free(inSamplesFftPtr);
    Module._free(inSampleCountsFftPtr);
}

async function makeFilePublicWeb(filePath) {
    console.log("makeFilePublicWeb: ", filePath);
    if (!NwbModule) {
        console.error("NwbModule not initialized yet");
        postMessage({
            message: 'MAKE_FILE_PUBLIC_CALLBACK',
            fileName: filePath,
            fileData: [],
            status: "FAILED",
        });
        return;
    }
    let fileName = filePath;
    let FS = null;                
    // Try different possible locations for FS
    if (NwbModule.FS) {
        FS = NwbModule.FS;
    } else if (typeof FS !== 'undefined') {
        // FS is global
    } else if (NwbModule._FS) {
        FS = NwbModule._FS;
    }

    if (FS.existsSync(fileName)) {
        const readData = FS.readFile('/' + fileName);
        if (recordingFileWritable) {
            await recordingFileWritable.write(readData);
            await recordingFileWritable.close();
            console.log("recordingFileWritable closed");
        }
    }



    return;

    const fileSize = NwbModule.ccall('get_nwb_file_size', 'number', ['string'], [fileName]);
    console.log("fileSize: ", fileSize);

    if (fileSize < 0) {
        postMessage({
            message: 'MAKE_FILE_PUBLIC_CALLBACK',
            fileName: fileName,
            fileData: [],
            status: "FAILED",
        });
        return;
    }
    const buffer = NwbModule.ccall('malloc', 'number', ['number'], [fileSize]);
    const bytesRead = NwbModule.ccall('get_nwb_file_data', 'number', ['string', 'number', 'number', 'number'], [fileName, buffer, 0, fileSize]);
    console.log("bytesRead: ", bytesRead, fileSize);

    if (bytesRead > 0) {

        if (recordingFileWritable) {
            await recordingFileWritable.write(buffer);
            await recordingFileWritable.close();
            console.log("recordingFileWritable closed");
        }
        // recordingFileHandle.write(buffer, fileSize);
        // Convert the buffer to a JavaScript string
        // const fileData = NwbModule.UTF8ToString(buffer, bytesRead);
        // postMessage({
        //     message: 'MAKE_FILE_PUBLIC_CALLBACK',
        //     fileName: fileName,
        //     fileData: fileData,
        //     status: "SUCCESS",
        // });
    } else {
        // postMessage({
        //     message: 'MAKE_FILE_PUBLIC_CALLBACK',
        //     fileName: fileName,
        //     fileData: [],
        //     status: "FAILED",
        // });
        // return;
    }
    
    // Free the allocated memory
    NwbModule.ccall('free', null, ['number'], [buffer]);             
}

async function seekNwbFileBufferWeb(filePath, outSamples, outSamplesCount, outConfig, startIdx, endIdx, startChannel, endChannel, samplesLength, isStartOpeningFileWeb = false) {
    console.log("SECTION seekNwbFileBufferWeb: ", filePath, startIdx, endIdx, samplesLength);
    // FFI_PLUGIN_EXPORT int32_t nwbfile_seek_electrical_series(const char* path, short* outSamples, int* outSamplesCount, int* outConfig, int startTimeStamp, int endTimeStamp, int startChannel, int endChannel) {
    const result = NwbModule.ccall('nwbfile_seek_electrical_series', 'number', ['string', 'number', 'number', 'number', 'number', 'number', 'number', 'number'], [filePath, outSamples, outSamplesCount, outConfig, startIdx, endIdx, startChannel, endChannel]);
    
    if (result == 0) {
        console.log("seekNwbFileBufferWeb success " + result);
    } else {
        console.log("seekNwbFileBufferWeb failed " + result);
    }
    
    let outSamplesStart = outSamples / NwbModule.HEAP16.BYTES_PER_ELEMENT;
    let outSamplesBuffer = NwbModule.HEAP16.subarray(outSamplesStart, (outSamplesStart + samplesLength));
    let outSamplesCountStart = outSamplesCount / NwbModule.HEAP32.BYTES_PER_ELEMENT;
    let outSamplesCountBuffer = NwbModule.HEAP32.subarray(outSamplesCountStart, (outSamplesCountStart + 1));
    let outConfigStart = outConfig / NwbModule.HEAP32.BYTES_PER_ELEMENT;
    let outConfigBuffer = NwbModule.HEAP32.subarray(outConfigStart, (outConfigStart + 10));

    // loadedSamplesBuffer = (outSamplesBuffer).slice();
    // loadedSamplesCountBuffer = (outSamplesCountBuffer).slice();
    // loadedConfigBuffer = (outConfigBuffer).slice();
    loadedSamplesBuffer = (outSamplesBuffer).slice();
    loadedSamplesCountBuffer = (outSamplesCountBuffer).slice();
    if (isStartOpeningFileWeb) {
        loadedConfigBuffer = (outConfigBuffer).slice();
    }




    // trigger callback
    postMessage({
        message: 'SEEK_NWB_FILE_BUFFER_WEB_CALLBACK',
        arrSamples: loadedSamplesBuffer,
        arrSampleCount: loadedSamplesCountBuffer,
        outConfigBuffer: loadedConfigBuffer,
        startIdx: startIdx,
        endIdx: endIdx,
        startChannel: startChannel,
        endChannel: endChannel,
        isStartOpeningFileWeb: isStartOpeningFileWeb,
    });

    Module._free(outSamples);
    Module._free(outSamplesCount);
    Module._free(outConfig);
}