importScripts("wavfile.js");
var wav = new wavefile.WaveFile();

let maxBufferedSerialEmptyCount = 300;
let bufferedSerialEmptyValue = [];
let bufferedSerialEmptyCount = [];
let recordSignalsList;
let recordChannelCount = 1;

/** Dart Int16List (.o), JS Array, or Int16Array after postMessage. */
function parseVisibleSignalsList(visibleSignalsList, channelCount) {
    if (visibleSignalsList == null) {
        return new Int16Array(channelCount).fill(1);
    }
    if (visibleSignalsList instanceof Int16Array) {
        return visibleSignalsList;
    }
    if (visibleSignalsList.o != null) {
        return new Int16Array(visibleSignalsList.o);
    }
    if (Array.isArray(visibleSignalsList)) {
        return Int16Array.from(visibleSignalsList);
    }
    if (typeof visibleSignalsList.length === "number") {
        return Int16Array.from(visibleSignalsList);
    }
    console.warn("parseVisibleSignalsList: unexpected type, defaulting all visible", visibleSignalsList);
    return new Int16Array(channelCount).fill(1);
}

let startingCounter = 0;
let startingTimer = 0;
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

/**
 * Load a fresh NWB WASM instance. Required before each CREATE_NWB_FILE because
 * processing_init keeps the HDF5 file open in native globals; a second init on
 * the same module throws H5::FileIException.
 */
async function reinitializeNwbModule() {
    NwbModule = await NWBPlugin();
    self.NwbModule = NwbModule;
    return NwbModule;
}

function getNwbFilesystem() {
    if (!NwbModule) {
        return null;
    }
    if (NwbModule.FS) {
        return NwbModule.FS;
    }
    if (NwbModule._FS) {
        return NwbModule._FS;
    }
    return null;
}

function normalizeNwbFileName(fileName) {
    if (!fileName) {
        return '';
    }
    return fileName.replace(/^\/+/, '').replace(/\.wav$/i, '.nwb');
}

function nwbExistsInMemfs(fileName) {
    const FS = getNwbFilesystem();
    if (!FS) {
        return null;
    }
    const bare = normalizeNwbFileName(fileName);
    for (const path of [bare, '/' + bare]) {
        try {
            FS.readFile(path);
            return bare;
        } catch (_) {}
    }
    return null;
}

/** Load a disk-picked .nwb into WASM MEMFS so nwbfile_seek_electrical_series can open it. */
async function ensureNwbInMemfs(fileName, fileHandle) {
    const bare = normalizeNwbFileName(fileName);
    const existing = nwbExistsInMemfs(bare);
    if (existing) {
        console.log("NWB already in MEMFS:", existing);
        return existing;
    }
    if (!fileHandle || typeof fileHandle.getFile !== 'function') {
        console.error("NWB not in MEMFS and no fileHandle:", bare);
        return null;
    }
    const FS = getNwbFilesystem();
    if (!FS) {
        console.error("ensureNwbInMemfs: NwbModule FS unavailable");
        return null;
    }
    try {
        const file = await fileHandle.getFile();
        if (!file || file.size < 64) {
            console.error("ensureNwbInMemfs: file too small", file?.size);
            return null;
        }
        const buffer = new Uint8Array(await file.arrayBuffer());
        FS.writeFile(bare, buffer);
        console.log("Loaded NWB into MEMFS:", bare, buffer.length, "bytes");
        return bare;
    } catch (err) {
        console.error("ensureNwbInMemfs failed:", err);
        return null;
    }
}

async function prepareNwbFileForOpening(fileName, fileHandle, isStartOpeningFileWeb) {
    if (isStartOpeningFileWeb) {
        await reinitializeNwbModule();
    }
    return await ensureNwbInMemfs(fileName, fileHandle);
}

function postSeekOpenFailed(isStartOpeningFileWeb, isPlayback) {
    const message = isPlayback
        ? 'SEEK_NWB_FILE_BUFFER_WEB_CALLBACK_PLAYBACK'
        : 'SEEK_NWB_FILE_BUFFER_WEB_CALLBACK';
    postMessage({
        message: message,
        arrSamples: new Int16Array(0),
        arrSampleCount: new Int32Array(0),
        outConfigBuffer: new Int32Array(10),
        isStartOpeningFileWeb: isStartOpeningFileWeb,
        openFailed: true,
    });
}

async function handleOpenNwbFileWeb(eventFromMain, isPlayback) {
    let fileName = normalizeNwbFileName(eventFromMain.data.filePath);
    const startIdx = eventFromMain.data.startIdx;
    const endIdx = eventFromMain.data.endIdx;
    const startChannel = eventFromMain.data.startChannel;
    const endChannel = eventFromMain.data.endChannel;
    const fileHandle = eventFromMain.data.fileHandle;
    const isStartOpeningFileWeb = eventFromMain.data.isStartOpeningFileWeb;

    const readyPath = await prepareNwbFileForOpening(
        fileName,
        fileHandle,
        isStartOpeningFileWeb
    );
    if (!readyPath) {
        postSeekOpenFailed(isStartOpeningFileWeb, isPlayback);
        return;
    }
    fileName = readyPath;

    console.log("!!@!!START OPENING FILE WEB, fileName:", fileName);

    const samplesLength = endIdx - startIdx;
    const loadedChannelCount = endChannel - startChannel + 1;
    const loadedOutSamples = NwbModule._malloc(
        loadedChannelCount * samplesLength * NwbModule.HEAP16.BYTES_PER_ELEMENT
    );
    const loadedOutSamplesCount = NwbModule._malloc(
        loadedChannelCount * NwbModule.HEAP32.BYTES_PER_ELEMENT
    );
    const loadedOutConfig = NwbModule._malloc(10 * NwbModule.HEAP32.BYTES_PER_ELEMENT);
    console.log("!!@!!seekNwbFileBufferWeb loadedChannelCount", loadedChannelCount);
    seekNwbFileBufferWeb(
        fileName,
        loadedOutSamples,
        loadedOutSamplesCount,
        loadedOutConfig,
        startIdx,
        endIdx,
        startChannel,
        endChannel,
        samplesLength,
        isStartOpeningFileWeb,
        isPlayback
    );
}

function callProcessingInit(filePath, sampleRate, channelCount, deviceInfo, deviceManufacturer) {
    if (!filePath || channelCount <= 0 || sampleRate <= 0) {
        console.error("Invalid NWB init params", { filePath, sampleRate, channelCount });
        return -1;
    }
    try {
        return NwbModule.ccall(
            'processing_init',
            'number',
            ['string', 'number', 'number', 'string', 'string'],
            [filePath, sampleRate, channelCount, deviceInfo, deviceManufacturer]
        );
    } catch (err) {
        console.error("processing_init threw:", err);
        return -1;
    }
}

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

function canPostLivePlayback() {
    return isRecording == -1 && !isThresholding;
}

function serialProcessingOk(serialResult) {
    return serialResult > 0 || serialResult === 0;
}

function resolveSerialFrameCount(serialResult, outSampleCountsBuffer, totalChannel, serialPacketLen, byteLength) {
    let frameCount = serialResult > 0 ? serialResult : 0;
    for (let i = 0; i < totalChannel; i++) {
        const c = outSampleCountsBuffer[i] | 0;
        if (c > 0 && c < serialPacketLen) {
            frameCount = c;
            break;
        }
    }
    if (frameCount <= 0) {
        frameCount = Math.max(1, Math.floor((byteLength / 2) / Math.max(1, totalChannel)));
    }
    return frameCount;
}

function buildSerialLiveChunkViews(inSamplesBuffer, outSampleCountsBuffer, totalChannel, serialPacketLen, frameCount) {
    const chunkViews = [];
    let offset = 0;
    for (let i = 0; i < totalChannel; i++) {
        let n = outSampleCountsBuffer[i] | 0;
        if (n <= 0 || n >= serialPacketLen) {
            n = frameCount;
        }
        if (n <= 0) continue;
        chunkViews.push(inSamplesBuffer.slice(offset, offset + n));
        offset += n;
    }
    if (chunkViews.length === 0 && frameCount > 0) {
        for (let i = 0; i < totalChannel; i++) {
            const start = i * serialPacketLen;
            chunkViews.push(inSamplesBuffer.slice(start, start + frameCount));
        }
    }
    if (chunkViews.length === 0 && frameCount > 0) {
        chunkViews.push(inSamplesBuffer.slice(0, Math.min(frameCount, inSamplesBuffer.length)));
    }
    return chunkViews;
}

function postSerialLivePlaybackChunk(inSamplesBuffer, outSampleCountsBuffer, serialResult, totalChannel, serialPacketLen, byteLength) {
    if (!canPostLivePlayback() || !serialProcessingOk(serialResult)) {
        return;
    }
    const frameCount = resolveSerialFrameCount(
        serialResult, outSampleCountsBuffer, totalChannel, serialPacketLen, byteLength
    );
    const chunkViews = buildSerialLiveChunkViews(
        inSamplesBuffer, outSampleCountsBuffer, totalChannel, serialPacketLen, frameCount
    );
    if (chunkViews.length > 0) {
        postMessage({
            message: "LIVE_PLAYBACK_CHUNK",
            chunkViews: chunkViews,
        });
    }
}
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
            // console.log("Module" , Module, Module._processing_process_threshold);
            sampleRate = eventFromMain.data.sampleRate;
            channelCount = eventFromMain.data.channelCount;
            drawSurfaceWidth = eventFromMain.data.drawSurfaceWidth;

            console.log("INITIALIZE_MICROPHONE : ", sampleRate, channelCount, drawSurfaceWidth);
            // sampleRate = eventFromMain.data.sampleRate;
            Module._processing_init();
            Module._processing_set_channel_count(channelCount);
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

            console.log("onDrawingBufferAllocated - javascript", channelCount, drawingDataBufferList[0].length, drawSurfaceWidth);
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
            console.log("Drawing Count Buffer List: INIT MICROPHONE ", channelCount,drawingCountBufferList);


            outEventPositionPtr = Module._malloc(MAX_EVENT_MARKERS * Module.HEAPF64.BYTES_PER_ELEMENT);
            outEventPositionPtrStart = outEventPositionPtr / Module.HEAPF64.BYTES_PER_ELEMENT;
            outEventPositionBuffer = Module.HEAPF64.subarray(outEventPositionPtrStart, (outEventPositionPtrStart + MAX_EVENT_MARKERS));
            for (i = 0; i < channelCount; i++) {
                drawingCountBuffer[i] = drawSurfaceWidth * 5;
            }
            console.log("onDrawingBufferAllocated MIC - javascript", channelCount, drawingCountBufferList, drawSurfaceWidth);
            postMessage({
                "message": "ALLOCATE_DRAWING_DATA_BUFFER",
                "drawingDataBufferList": drawingDataBufferList,
                "drawingCountBufferList": drawingCountBufferList,
                "channelCount": channelCount,
                "eventPositions": outEventPositionBuffer,
            });
            // END DRAWING COUNTER SETUP            

            // currentDataBuffersPtr = curBufferPtr;
            // console.log("Module: ", Module);
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
            initWithConfig(eventFromMain.data.config);
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
            // console.log("DISPLAY_MICROPHONE_DATA123");
            // return;
            // _drawSurfaceWidth = eventFromMain.data.drawSurfaceWidth;
            channelCount = eventFromMain.data.channelCount;
            _displayTimeMs = eventFromMain.data.displayTimeMs;
            drawSurfaceWidth = eventFromMain.data.drawSurfaceWidth;
            startPositionIdx = eventFromMain.data.startPositionIdx;
            endPositionIdx = eventFromMain.data.endPositionIdx;
            eventLabels = JSON.parse(eventFromMain.data.eventLabels);
            eventPositions = JSON.parse(eventFromMain.data.eventPositions);
            
            outSignalPtr = undefined;
            outSamplesPtr = undefined;
            outSampleCountsDrawingPtr = undefined;
            outEventIndicesPtr = undefined;
            outEventCountPtr = undefined;
            inEventIndicesPtr = undefined;
            
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

                // console.log("AUDIO DRAWING: ", startPositionIdx, endPositionIdx, drawSurfaceWidth, totalChannel, " ---- ", outSampleCountsDrawingBuffer);
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
                    try{
                        if (inTotalEvents > 0) {
                            outEventPositionBuffer.set(outEventIndicesBuffer.subarray(0, inTotalEvents));
                        }
                            // console.log("outSampleCountsDrawingBuffer: " , channelCount, outSampleCountsDrawingBuffer.length, outSampleCountsDrawingBuffer);
                        for (let i = 0; i < channelCount; i++) {
                            const outSampleCount = outSampleCountsDrawingBuffer[i];
                            const slicedArray = outSamplesBuffer.subarray( i * outSampleCount, (i + 1) * outSampleCount).slice();
                            // const slicedCountArray = outSampleCountsBuffer.subarray(i, i + 1).slice();
                            // console.log("drawingCountBufferList: ",  slicedArray.length);
                            drawingDataBufferList[i].set(slicedArray, 0);
                            drawingCountBufferList[i] = slicedArray.length;
                        }
                        // console.log("drawingDataBufferList: ", drawingDataBufferList[0].subarray(1700,1750));
                        const data = {
                            "message": "INPUT_MICROPHONE_BUFFER_FINISHED",
                            "channelIdx": 0,
                            "bufferViews": drawingDataBufferList,
                            "bufferCountViews": drawingCountBufferList,
                        };
                        postMessage(data);
                    }catch(err) {
                        console.log("ERR MIMIC SHARED DRAWING BUFFERR", err);
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

            }catch(err){
                console.log("err123123");
                console.log(err);
            } finally {
                try {
                    if (outSamplesPtr !== undefined) Module._free(outSignalPtr);
                    if (outSamplesPtr !== undefined) Module._free(outSamplesPtr);
                    if (outSampleCountsDrawingPtr !== undefined) Module._free(outSampleCountsDrawingPtr);
                    if (outEventIndicesPtr !== undefined) Module._free(outEventIndicesPtr);
                    if (outEventCountPtr !== undefined) Module._free(outEventCountPtr);
                    if (inEventIndicesPtr !== undefined) Module._free(inEventIndicesPtr);
                }catch(err123) {
                    console.log("err123");
                    console.log(err123)
                }

            }            
        break;
        case "INPUT_MICROPHONE_BUFFER":
            // Prepare input data pointer
            data = eventFromMain.data.microphoneDataBuffers.slice();
            channelIdx = eventFromMain.data.channelIdx;
            inDataPtr = Module._malloc(data.length * Module.HEAPU8.BYTES_PER_ELEMENT);
            inDataPtrStart = inDataPtr / Module.HEAPU8.BYTES_PER_ELEMENT;
            inDataArr = Module.HEAPU8.subarray(inDataPtrStart, (inDataPtrStart + data.length));
            
            totalChannel = channelCount;
            inSamplesPtr = Module._malloc( packetLen * totalChannel * Module.HEAP16.BYTES_PER_ELEMENT);
            inSamplesPtrStart = inSamplesPtr / Module.HEAP16.BYTES_PER_ELEMENT;
            inSamplesBuffer = Module.HEAP16.subarray(inSamplesPtrStart, (inSamplesPtrStart + packetLen * totalChannel));
            outSampleCountsPtr = Module._malloc( totalChannel * Module.HEAP32.BYTES_PER_ELEMENT);
            outSampleCountsPtrStart = outSampleCountsPtr / Module.HEAP32.BYTES_PER_ELEMENT;
            outSampleCountsBuffer = Module.HEAP32.subarray(outSampleCountsPtrStart, (outSampleCountsPtrStart + totalChannel));


            for (let i = 0; i < totalChannel; i++) {
                outSampleCountsBuffer[i] = data.length / 2;
            }
            inDataArr.set(data);

            let micResult = -1;
            try{
                micResult = Module._processing_process_microphone_stream(
                    inSamplesPtr,
                    outSampleCountsPtr,
                    inDataPtr,
                    data.length
                );
            }catch(err) {
                console.log("PROCESS MICROPHONE STREAM ERROR: ", inSamplesBuffer, outSampleCountsBuffer, inDataArr, data,err);
                Module._free(inSamplesPtr);
                Module._free(inDataPtr);
                Module._free(outSampleCountsPtr);
    
                return;

            }
            if (micResult === 0 && isRecording == -1 && !isThresholding) {
                let frameCount = outSampleCountsBuffer[0];
                if (frameCount <= 0) {
                    frameCount = Math.floor(data.length / 2);
                }
                const chunkViews = [];
                for (let i = 0; i < totalChannel; i++) {
                    const n = outSampleCountsBuffer[i] > 0 ? outSampleCountsBuffer[i] : frameCount;
                    if (n <= 0) continue;
                    const start = i * packetLen;
                    chunkViews.push(inSamplesBuffer.slice(start, start + n));
                }
                if (chunkViews.length > 0) {
                    postMessage({
                        message: "LIVE_PLAYBACK_CHUNK",
                        chunkViews: chunkViews,
                    });
                }
            }
            
            let selectedChannel = 0;

            let FFT_30HZ_LENGTH = 32;
            let FFT_WINDOW_TIME_LENGTH = 4;          
            let windowCountFft = Math.floor( (10.0 * 128) / Math.floor(512 * 0.01) );
            let windowSizeFft = (FFT_30HZ_LENGTH * FFT_WINDOW_TIME_LENGTH);
      
            try {
                // processFftMicrophoneData(channelCount, selectedChannel, windowCountFft, windowSizeFft, [inSamplesBuffer], outSampleCountsBuffer);
            }catch(err) {
                console.log("err: ", err);
                return
            }

            if (isRecording == 0) {
                let samplesLength = outSampleCountsBuffer[0];
                let channelsLength = 1;

                let samplesPtr = NwbModule._malloc(samplesLength * NwbModule.HEAP16.BYTES_PER_ELEMENT);
                let samplesPtrStart = samplesPtr / NwbModule.HEAP16.BYTES_PER_ELEMENT;
                let samplesBuffer = NwbModule.HEAP16.subarray(samplesPtrStart, (samplesPtrStart + samplesLength));
                samplesBuffer.set(inSamplesBuffer.subarray(0, samplesLength));
                
                let samplesCtrPtr = NwbModule._malloc(channelsLength * NwbModule.HEAP32.BYTES_PER_ELEMENT);
                let samplesCtrPtrStart = samplesCtrPtr / NwbModule.HEAP32.BYTES_PER_ELEMENT;
                let samplesCtrBuffer = NwbModule.HEAP32.subarray(samplesCtrPtrStart, (samplesCtrPtrStart + channelsLength));
                samplesCtrBuffer[0] = samplesLength;

                NwbModule._nwbfile_add_electrical_series(samplesPtr, samplesCtrPtr, 0, 1, isRecording);
                NwbModule._free(samplesPtr);
                NwbModule._free(samplesCtrPtr);
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
            // if (micResult >= 0) {
            // }
            // console.log("micResult: ", micResult);
        

        break;
        case "SET_CHANNEL_FILTER_ENABLED":
            const channelIndex = eventFromMain.data.channelIndex;
            const enabled = eventFromMain.data.enabled == 1 ? true : false;
            console.log("_processing_set_channel_filter_enabled WEB ", channelIndex, enabled);
            Module._processing_set_channel_filter_enabled(channelIndex, enabled);

        break;

        case "SET_BAND_FILTER":
            const bandChannelIdx = eventFromMain.data.channelIdx;
            const lowFreq = eventFromMain.data.lowFreq;
            const highFreq = eventFromMain.data.highFreq;
            console.log("lowFreq, highFreq");
            console.log(lowFreq, highFreq);
            Module._processing_set_band_filter(bandChannelIdx, lowFreq, highFreq);
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
            postMessage({
                "message": "SET_DEFAULT_DEVICE_PARAMETERS",
                "sampleRate": sampleRate, 
                "channelCount": channelCount, 
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
            totalChannel = channelCount;
            inSamplesPtr = Module._malloc( serialPacketLen * totalChannel * Module.HEAP16.BYTES_PER_ELEMENT);
            inSamplesPtrStart = inSamplesPtr / Module.HEAP16.BYTES_PER_ELEMENT;
            inSamplesBuffer = Module.HEAP16.subarray(inSamplesPtrStart, (inSamplesPtrStart + serialPacketLen * totalChannel));
            inSamplesBuffer.fill(0, 0, serialPacketLen * totalChannel);

            outSampleCountsPtr = Module._malloc( totalChannel * Module.HEAP32.BYTES_PER_ELEMENT);
            outSampleCountsPtrStart = outSampleCountsPtr / Module.HEAP32.BYTES_PER_ELEMENT;
            outSampleCountsBuffer = Module.HEAP32.subarray(outSampleCountsPtrStart, (outSampleCountsPtrStart + totalChannel));

            // Slot stride expected by WASM (see processing_process_sample_stream).
            for (let i = 0; i < totalChannel; i++) {
                outSampleCountsBuffer[i] = serialPacketLen;
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
            postSerialLivePlaybackChunk(
                inSamplesBuffer,
                outSampleCountsBuffer,
                serialResult,
                totalChannel,
                serialPacketLen,
                data.length
            );

            if (serialProcessingOk(serialResult)) {
                // RECORD SERIAL
                // if (startingTimer == 0) {
                //     startingTimer = Date.now();
                //     startingCounter = 0;
                // } else 
                // if ( Date.now() - startingTimer > 1000) {
                //     startingTimer = Date.now();
                //     console.log("Starting Timer: ", startingTimer, "Current Time: ", Date.now(), "Time Difference: ", Date.now() - startingTimer, "Starting Counter - channel 0: ", startingCounter, "outSampleCountsBuffer[0]: ", outSampleCountsBuffer[0]);
                //     startingCounter = 0;
                // } else {
                //     startingCounter += outSampleCountsBuffer[0];
                // }

                if (isRecording == 0) {
                    // Buffer samples per channel - accumulate samples when length > 0

                    let recordCombinedIdx = 0;
                    let isFoundEmpty = false;
                    for (let i = 0; i < totalChannel; i++) {
                        let samplesLength = outSampleCountsBuffer[i];
                        if (samplesLength == 0) {
                            isFoundEmpty = true;
                        }
                        const tempArray = inSamplesBuffer.subarray(recordCombinedIdx, recordCombinedIdx + samplesLength);
                        bufferedSerialEmptyValue[i].set(tempArray, bufferedSerialEmptyCount[i]);
                        bufferedSerialEmptyCount[i] += samplesLength;
                        recordCombinedIdx += data.length
                    }
                    if (isFoundEmpty) {
                        return;
                    } 
                    // buffer if 0 | if > 0 also buffer in a array

                    let combinedIdx = 0;
                    let samplesCtrPtr = NwbModule._malloc(recordChannelCount * NwbModule.HEAP32.BYTES_PER_ELEMENT);
                    let samplesCtrPtrStart = samplesCtrPtr / NwbModule.HEAP32.BYTES_PER_ELEMENT;
                    let samplesCtrBuffer = NwbModule.HEAP32.subarray(samplesCtrPtrStart, (samplesCtrPtrStart + recordChannelCount));
                    let segmentIndex = 0;
                    // for (let i = 0; i < totalChannel; i++) {
                    //     let samplesLength = outSampleCountsBuffer[i];    
                    //     // hardcode -- buffer it
                    //     if (samplesLength == 0) {
                    //         samplesLength = 1;
                    //     }
                    //     samplesCtrBuffer[i] = samplesLength;
                    //     combinedIdx += data.length;
                    //     segmentIndex += samplesLength;
                    // }
                    let recordIdx = 0;
                    for (let i = 0; i < totalChannel; i++) {
                        if (recordSignalsList[i] == 0) continue;
                        
                        let samplesLength = bufferedSerialEmptyCount[i];    
                        samplesCtrBuffer[recordIdx] = samplesLength;
                        combinedIdx += data.length;
                        segmentIndex += samplesLength;
                        recordIdx++;
                    }
                    let samplesPtr = NwbModule._malloc(segmentIndex * NwbModule.HEAP16.BYTES_PER_ELEMENT);
                    let samplesPtrStart = samplesPtr / NwbModule.HEAP16.BYTES_PER_ELEMENT;
                    let samplesBuffer = NwbModule.HEAP16.subarray(samplesPtrStart, (samplesPtrStart + segmentIndex));

                    // Copy data sequentially: [ch0_samples, ch1_samples, ch2_samples, ...]
                    recordIdx = 0;
                    combinedIdx = 0;
                    segmentIndex = 0;
                    // console.log("INSAMPLES BUFFER: ", inSamplesBuffer);
                    for (let i = 0; i < totalChannel; i++) {
                        if (recordSignalsList[i] == 0) continue;

                        let samplesLength = bufferedSerialEmptyCount[i];    
                        // hardcode -- buffer it
                        // if (samplesLength == 0) {
                        //     samplesLength = 1;
                        //     const tempArray = new Int16Array(1);
                        //     samplesBuffer.set(tempArray, segmentIndex);
                        // } else {
                        //     const tempArray = inSamplesBuffer.subarray(combinedIdx, combinedIdx + samplesLength);
                        //     // console.log("samplesLength: ", samplesLength, "tempArray: ", tempArray);
                        //     samplesBuffer.set(tempArray, segmentIndex);
                        // }
                        const tempArray = bufferedSerialEmptyValue[i].subarray(0, bufferedSerialEmptyCount[i]);
                        // console.log("INDEX : ", i, recordSignalsList[i], recordSignalsList[i] == 0);
                        // console.log("samplesLength: ", samplesLength, "tempArray: ", tempArray);
                        samplesBuffer.set(tempArray, segmentIndex);
                        combinedIdx += data.length;
                        segmentIndex += samplesLength;
                    }



                    // NwbModule._nwbfile_add_electrical_series(inSamplesPtr, outSampleCountsPtr, 0, 1, isRecording);
                    // console.log("INSAMPLES BUFFER: ", inSamplesBuffer);
                    // console.log("Data Length: ", data.length, "SAMPLES CTR BUFFER: ", samplesCtrBuffer);
                    // // console.log("SAMPLES BUFFER: ", samplesBuffer);
                    // console.log("TOTAL CHANNEL: ", recordChannelCount, "samplesBuffer: ", samplesBuffer);
    
                    NwbModule._nwbfile_add_electrical_series(samplesPtr, samplesCtrPtr, 0, recordChannelCount, isRecording);
                    NwbModule._free(samplesPtr);
                    NwbModule._free(samplesCtrPtr);

                    // reset buffer after writing to file segment.
                    for (let i = 0; i < totalChannel; i++) {
                        let endClearIndex = bufferedSerialEmptyCount[i];
                        if (endClearIndex > 140) {
                            endClearIndex = 300;
                        } else {
                            endClearIndex *= 2;
                        }
                        bufferedSerialEmptyValue[i].fill(0, 0, endClearIndex);
                        bufferedSerialEmptyCount[i] = 0;
                    }
                }
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
                    outSamplesBuffer.fill(0, i * startPosMultiplier, i * startPosMultiplier + startPosMultiplier);
                }
                  
                // console.log("SERIAL DRAWING: ", startPositionIdx, endPositionIdx, drawSurfaceWidth, totalChannel);
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
            console.log("SET_THRESHOLD_AVERAGE_SAMPLE: ", avgSampleCount);
            Module._processing_set_averaged_sample_count(avgSampleCount);
        break;
        case "SET_THRESHOLD_VALUE":
            let thresholdValue = eventFromMain.data.thresholdValue;
            console.log("SET_THRESHOLD_VALUE: ", thresholdValue);
            Module._processing_set_threshold(thresholdValue);
        break;
        case "SET_THRESHOLD_IS_THRESHOLDING":
            isThresholding = eventFromMain.data.isThresholding;
            console.log("SET_THRESHOLD_IS_THRESHOLDING: ", isThresholding);
            Module._processing_set_is_thresholding(isThresholding);
        break;
        case "SET_THRESHOLD_TRIGGER_TYPE":
            let eventThresholdTriggeredType = eventFromMain.data.eventThresholdTriggeredType;
            console.log("SET_THRESHOLD_TRIGGER_TYPE: ", eventThresholdTriggeredType);
            Module._processing_set_averaging_trigger_type(eventThresholdTriggeredType);
        break;
        case "CREATE_NWB_FILE":
            if (typeof NWBPlugin === 'undefined') {
                console.error("NWBPlugin not loaded yet");
                return;
            }
            try {
                await reinitializeNwbModule();
            } catch (err) {
                console.error("Failed to reinitialize NWB module:", err);
                postMessage({
                    message: "NWB_FILE_CREATE_FAILED",
                    error: String(err),
                });
                return;
            }
            console.log("CREATE_NWB_FILE: ", eventFromMain.data);
            let recordedFileCookie = eventFromMain.data.recordedFileCookie;

            console.log("COOKIE WORKER: ", recordedFileCookie);
            let FS = getNwbFilesystem();
            if (recordedFileCookie !== undefined && recordedFileCookie != "") {
                let arrRecordedFiles = recordedFileCookie.split(";");
                let flag = false;
                try {
                    FS.accessSync(path, FS.constants.F_OK);
                    console.log(`File ${path} exists synchronously.`);
                    flag = true;
                } catch (e) {
                    console.log(`File ${path} does not exist synchronously.`);
                    flag = false;
                }         
                if (flag) {
                    for (let strFile in arrRecordedFiles) {
                        try{
                            FS.unlink(strFile);
                        }catch(err) {
                            console.log("ERROR UNLINK", strFile);
                        }
                    }
                }
            }
                
            let filePath = eventFromMain.data.filePath;
            osFilePath = filePath;
            console.log("OS FILE PATH : ", osFilePath);

            // if filePath.contains(".wav") then it is a wav file
            let isWavFileOpened = eventFromMain.data.isWavFile !== undefined && eventFromMain.data.isWavFile ? true:false;
            if (isWavFileOpened) {
                isRecording = -1;

                let fileHandle = eventFromMain.data.fileHandle;
                const readData = await fileHandle.getFile();
                console.log("Read Data: ", readData);
                if (readData) {
                    const fileBuffer = await readData.arrayBuffer();
                    wav.fromBuffer(new Uint8Array(fileBuffer), true);
                    // Spike Recorder WAV exports are often 32-bit float (format 3), not PCM.
                    // getSamples(false, Int16Array) on float WAV yields silence; convert first.
                    if (wav.bitDepth === '32f' || wav.bitDepth === '64' || wav.fmt.audioFormat === 3) {
                        wav.toBitDepth('16');
                    }
                    let wavSampleRate = wav.fmt.sampleRate;
                    let wavChannelCount = wav.fmt.numChannels;
                    if (wavChannelCount > 1) {
                        deviceInfo = "SpikeRecorder Device|||";
                        deviceManufacturer = "SpikeRecorder Systems@@@LegacyFormat";
                    } else {
                        deviceInfo = "Audio|||";
                        deviceManufacturer = "SpikeRecorder Systems";
                    }

                    let nwbFilePath = fileHandle.name.replace(".wav", ".nwb");
                    console.log("NWB FILE PATHzzz: ", nwbFilePath);
                    console.log("WAV metadata:", { wavSampleRate, wavChannelCount });
                    const result = callProcessingInit(
                        nwbFilePath, wavSampleRate, wavChannelCount, deviceInfo, deviceManufacturer
                    );
                    if (result !== 0) {
                        postMessage({
                            message: "NWB_FILE_CREATE_FAILED",
                            error: "processing_init returned " + result,
                            filePath: nwbFilePath,
                        });
                        return;
                    }
                    bufferedSerialEmptyValue = [];
                    bufferedSerialEmptyCount = [];
                    for (let i = 0; i < wavChannelCount; i++) {
                        const tempArray = new Int16Array(maxBufferedSerialEmptyCount)
                        bufferedSerialEmptyValue.push( tempArray );
                        bufferedSerialEmptyCount.push( 0 );
                    }

                    let samplesCtrPtr = NwbModule._malloc(wavChannelCount * NwbModule.HEAP32.BYTES_PER_ELEMENT);
                    let samplesCtrPtrStart = samplesCtrPtr / NwbModule.HEAP32.BYTES_PER_ELEMENT;
                    let samplesCtrBuffer = NwbModule.HEAP32.subarray(samplesCtrPtrStart, (samplesCtrPtrStart + wavChannelCount));

                    // wav.data.samples is raw PCM bytes (Uint8Array). Decode to int16 and split
                    // into planar channel arrays — NWB expects [ch0..chN] contiguous (see nwbfile_processing_plugin_web.cpp).
                    const decoded = wav.getSamples(false, Int16Array);
                    const channelArrays =
                        wav.fmt.numChannels === 1 ? [decoded] : decoded;
                    let segmentIndex = 0;
                    for (let i = 0; i < wav.fmt.numChannels; i++) {
                        samplesCtrBuffer[i] = channelArrays[i].length;
                        segmentIndex += channelArrays[i].length;
                    }
                    let samplesPtr = NwbModule._malloc(segmentIndex * NwbModule.HEAP16.BYTES_PER_ELEMENT);
                    let samplesPtrStart = samplesPtr / NwbModule.HEAP16.BYTES_PER_ELEMENT;
                    let samplesBufferRecording = NwbModule.HEAP16.subarray(
                        samplesPtrStart,
                        samplesPtrStart + segmentIndex
                    );
                    let writeOffset = 0;
                    // for (let i = 0; i < wav.fmt.numChannels; i++) {
                    for (let i = wav.fmt.numChannels - 1; i >= 0; i--) {
                        const ch = channelArrays[i];
                        samplesBufferRecording.set(ch, writeOffset);
                        writeOffset += ch.length;
                    }

                    NwbModule._nwbfile_add_electrical_series(samplesPtr, samplesCtrPtr, 0, wav.fmt.numChannels, 1);
                    NwbModule._free(samplesPtr);
                    NwbModule._free(samplesCtrPtr);
                    isRecording = -1;

                    postMessage({
                        message: "NWB_FILE_CREATED",
                        result: nwbFilePath,
                        isWavFile: true,
                    });
                }
                return;
            } else {
                isRecording = 0;

            }


            let nwbSampleRate = eventFromMain.data.sampleRate;
            let nwbChannelCount = eventFromMain.data.channelCount;
            recordSignalsList = parseVisibleSignalsList(
                eventFromMain.data.visibleSignalsList,
                nwbChannelCount
            );
            recordChannelCount = eventFromMain.data.visibleChannelCount;
            if (recordSignalsList.length < nwbChannelCount) {
                const padded = new Int16Array(nwbChannelCount).fill(1);
                padded.set(recordSignalsList);
                recordSignalsList = padded;
            }
            console.log(
                "CREATE_NWB_FILE visible channels:",
                recordChannelCount,
                "mask:",
                Array.from(recordSignalsList)
            );

            bufferedSerialEmptyValue = [];
            bufferedSerialEmptyCount = [];
            for (let i = 0; i < nwbChannelCount; i++) {
                const tempArray = new Int16Array(maxBufferedSerialEmptyCount)
                bufferedSerialEmptyValue.push( tempArray );
                bufferedSerialEmptyCount.push( 0 );
            }

            console.log("CREATE nwbChannelCount: ", nwbChannelCount);
            // CHANGE OF WORKFLOW
            // recordingFileHandle = eventFromMain.data.fileHandle;
            // recordingFileWritable = await recordingFileHandle.createWritable();
            
            let deviceInfoPointer = eventFromMain.data.deviceInfoPointer;
            let deviceManufacturerPointer = eventFromMain.data.deviceManufacturerPointer;
            // NwbModule._processing_init(filePath, nwbSampleRate, nwbChannelCount, deviceInfoPointer, deviceManufacturerPointer);
            const result = callProcessingInit(
                filePath, nwbSampleRate, recordChannelCount, deviceInfoPointer, deviceManufacturerPointer
            );
            console.log("PROCESSING INIT result: ", result);
            if (result !== 0) {
                postMessage({
                    message: "NWB_FILE_CREATE_FAILED",
                    error: "processing_init returned " + result,
                    filePath: filePath,
                });
                return;
            }
            
            // Initialize buffers for accumulating samples
            // bufferedSamplesPerChannel = [];
            // bufferedSampleCounts = [];
            // for (let i = 0; i < nwbChannelCount; i++) {
            //     bufferedSamplesPerChannel[i] = new Int16Array(0);
            //     bufferedSampleCounts[i] = 0;
            // }
            
            postMessage({
                "message": "NWB_FILE_CREATED",
                "result": filePath,
                "isWavFile": osFilePath.endsWith(".wav")? true : false,
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
            // let tempNwbChannelCount = eventFromMain.data.channelCount;
            let tempNwbChannelCount =
                recordChannelCount > 0 ? recordChannelCount : totalChannel;
            let isFinishRecording = eventFromMain.data.isFinishRecording;

            console.log("samples isFinishRecording: ", isFinishRecording, "samples length:", samples ? samples.length : 0, "samplesCount length:", samplesCount ? samplesCount.length : 0);
            // console.log("samples: ", samples, samplesCount, nwbSelectedChannel, tempNwbChannelCount, isFinishRecording);
            if (isFinishRecording == 1){ // FINISH RECORDING
                // Flush any remaining buffered samples before finishing
                // flushBufferedSamples();
                
                // When finishing, Dart passes empty arrays (Int16List(0), Int32List(0))
                // Native code requires samplesCount[i] > 0, so we allocate minimum valid data
                // and zero-fill it to avoid writing gibberish
                const minSamplesPerChannel = 1; // Minimum required: 1 sample per channel
                console.log("FINISH RECORDING: ", tempNwbChannelCount, "minSamplesPerChannel: ", minSamplesPerChannel, "tempNwbChannelCount: ", tempNwbChannelCount);
                
                // Allocate memory for sample counts
                let samplesCtrPtr = NwbModule._malloc(tempNwbChannelCount * NwbModule.HEAP32.BYTES_PER_ELEMENT);
                let samplesCtrPtrStart = samplesCtrPtr / NwbModule.HEAP32.BYTES_PER_ELEMENT;
                let samplesCtrBuffer = NwbModule.HEAP32.subarray(samplesCtrPtrStart, (samplesCtrPtrStart + tempNwbChannelCount));
                console.log("samplesCtrBuffer: ", samplesCtrBuffer);
                // Set sample counts to minimum required (1 per channel)
                samplesCtrBuffer.fill(minSamplesPerChannel);
                
                // Calculate total samples needed (sum of all channel sample counts)
                // Native code expects sequential data: [ch0_samples, ch1_samples, ch2_samples, ...]
                const totalSamples = tempNwbChannelCount * minSamplesPerChannel;
                
                let samplesPtr = NwbModule._malloc(totalSamples * NwbModule.HEAP16.BYTES_PER_ELEMENT);
                let samplesPtrStart = samplesPtr / NwbModule.HEAP16.BYTES_PER_ELEMENT;
                let samplesBufferRecording = NwbModule.HEAP16.subarray(samplesPtrStart, (samplesPtrStart + totalSamples));

                // Zero-fill to ensure no gibberish data
                samplesBufferRecording.fill(0);
                
                console.log("Finishing recording with zero-filled data, channelCount:", tempNwbChannelCount, "totalSamples:", totalSamples);
                NwbModule._nwbfile_add_electrical_series(samplesPtr, samplesCtrPtr, nwbSelectedChannel, tempNwbChannelCount, isFinishRecording);
                
                // Free memory after finish recording (native code copies the data immediately)
                NwbModule._free(samplesPtr);
                NwbModule._free(samplesCtrPtr);

                isRecording = -1;

            } else {
                isRecording = isFinishRecording;
                console.log("samples ISRECORDING: ", samples.length, "samplesCount.length: ", samplesCount.length);
                let samplesPtr = NwbModule._malloc(samples.length * NwbModule.HEAP16.BYTES_PER_ELEMENT);
                let samplesPtrStart = samplesPtr / NwbModule.HEAP16.BYTES_PER_ELEMENT;
                let samplesBufferRecording = NwbModule.HEAP16.subarray(samplesPtrStart, (samplesPtrStart + samples.length));
                samplesBufferRecording.set(samples);

                let samplesCtrPtr = NwbModule._malloc(samplesCount.length * NwbModule.HEAP32.BYTES_PER_ELEMENT);
                let samplesCtrPtrStart = samplesCtrPtr / NwbModule.HEAP32.BYTES_PER_ELEMENT;
                let samplesCtrBuffer = NwbModule.HEAP32.subarray(samplesCtrPtrStart, (samplesCtrPtrStart + samplesCount.length));
                samplesCtrBuffer.set(samplesCount);
                
                NwbModule._nwbfile_add_electrical_series(samplesPtr, samplesCtrPtr, nwbSelectedChannel, tempNwbChannelCount, isFinishRecording);
                
                // Free memory after adding electrical series (non-finish case)
                NwbModule._free(samplesPtr);
                NwbModule._free(samplesCtrPtr);
                // postMessage({
                //     "message": "ELECTRICAL_SERIES_ADDED",
                // });    
            }
        break;
        case "MAKE_FILE_PUBLIC":
            // "fileHandle": fileHandle,
            // "selectedChannel": selectedChannel,
            // "channelCount": channelCount,
            // "isFinishRecording": isFinishRecording,
            // CHANGE OF WORKFLOW
            recordingFileHandle = eventFromMain.data.fileHandle;
            recordingFileWritable = await recordingFileHandle.createWritable();
            makeFilePublicWeb(osFilePath);
            console.log("OS FILE PATH : $osFilePath");
        break;
        case "PROCESS_SERIAL_DATA_WEB_RESULT":
            let sampleData = eventFromMain.data.data;
            let sampleCounts = eventFromMain.data.sampleCounts;
            let serialChannelCount = eventFromMain.data.channelCount;
            // console.log("PROCESS_SERIAL_DATA_WEB_RESULT - Serial Channel Count: ", serialChannelCount);
            let serialEventLabels = JSON.parse(eventFromMain.data.eventLabels);
            let serialEventPositions = JSON.parse(eventFromMain.data.eventPositions);
            
            // console.log("PROCESS_SERIAL_DATA_WEB_RESULT - Sample Data: ", sampleData);
            // console.log("PROCESS_SERIAL_DATA_WEB_RESULT - Sample Counts: ", sampleCounts);
            // console.log("PROCESS_SERIAL_DATA_WEB_RESULT - Serial Event Labels: ", serialEventLabels);
            // console.log("PROCESS_SERIAL_DATA_WEB_RESULT - Serial Event Positions: ", serialEventPositions);

            let sampleDataPtr = Module._malloc(sampleData.length * Module.HEAP16.BYTES_PER_ELEMENT);
            let sampleDataPtrStart = sampleDataPtr / Module.HEAP16.BYTES_PER_ELEMENT;
            let sampleDataBuffer = Module.HEAP16.subarray(sampleDataPtrStart, (sampleDataPtrStart + sampleData.length));
            sampleDataBuffer.set(sampleData);

            let sampleCountsPtr = Module._malloc(sampleCounts.length * Module.HEAP32.BYTES_PER_ELEMENT);
            let sampleCountsPtrStart = sampleCountsPtr / Module.HEAP32.BYTES_PER_ELEMENT;
            let sampleCountsBuffer = Module.HEAP32.subarray(sampleCountsPtrStart, (sampleCountsPtrStart + sampleCounts.length));
            sampleCountsBuffer.set(sampleCounts);

            const resultSerialInject = Module.ccall(
                'processing_serial_data_result',
                'number',
                ['number', 'number', 'number'],
                [sampleDataPtr, sampleCountsPtr, serialChannelCount]
            );            
            // console.log("PROCESSING SERIAL DATA RESULT: ", resultSerialInject, sampleData, sampleCounts, serialChannelCount);
        break;
        case "SEEK_OPENING_FILE_WEB":
            try {
                console.log("start opening file web (seek playback)");
                await handleOpenNwbFileWeb(eventFromMain, true);
            } catch (err) {
                console.log("SEEK_OPENING_FILE_WEB error:", err);
                postSeekOpenFailed(eventFromMain.data.isStartOpeningFileWeb, true);
            }
        break;
        // Entry point for seek and open file web
        case "CONVERT_WAV_TO_NWB": // change to CREATE_NWB_FILE
            try{
                console.log("convert wav to nwb");
                let fileName = eventFromMain.data.filePath;
                let startIdx = eventFromMain.data.startIdx;
                let endIdx = eventFromMain.data.endIdx;
                let startChannel = eventFromMain.data.startChannel;
                let endChannel = eventFromMain.data.endChannel;
                let fileHandle = eventFromMain.data.fileHandle;

                const readData = await fileHandle.getFile();
                if (readData) {
                    const fileBuffer = await readData.arrayBuffer();
                    wav.fromBuffer(fileBuffer,true);
                    const result = NwbModule.ccall(
                        'processing_init',
                        'number',
                        ['string', 'number', 'number', 'string', 'string'],
                        // [filePath, nwbSampleRate, nwbChannelCount, deviceInfoPointer, deviceManufacturerPointer]
                        [filePath, nwbSampleRate, recordChannelCount, deviceInfoPointer, deviceManufacturerPointer]
                    );
                            
                    NwbModule._nwbfile_add_electrical_series(flattenedList, samplesCount, 0, wav.fmt.numChannels, 1);
                }

            }catch(err){
                
            }
        break;
        case "START_OPENING_FILE_WEB":
            try {
                console.log("start opening file web");
                await handleOpenNwbFileWeb(eventFromMain, false);
            } catch (err) {
                console.log("START_OPENING_FILE_WEB error:", err);
                postSeekOpenFailed(eventFromMain.data.isStartOpeningFileWeb, false);
            }
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

/**
 * Flush buffered samples to NWB file
 * Combines all buffered samples per channel and records them
 */
function flushBufferedSamples() {
    if (!NwbModule) {
        return;
    }

    // Determine channel count - use totalChannel if available, otherwise use buffered array length
    // const channelCountToUse = (typeof totalChannel !== 'undefined' && totalChannel > 0) 
    //     ? totalChannel 
    //     : Math.max(bufferedSamplesPerChannel.length, (typeof channelCount !== 'undefined' ? channelCount : 1));
    
    // // Check if there are any buffered samples to flush
    // let hasSamples = false;
    // for (let i = 0; i < channelCountToUse; i++) {
    //     if (i < bufferedSamplesPerChannel.length && bufferedSamplesPerChannel[i] && bufferedSamplesPerChannel[i].length > 0) {
    //         hasSamples = true;
    //         break;
    //     }
    // }
    
    // // If no samples buffered, ensure at least 1 sample per channel for NWB requirement
    // // Calculate total samples needed (sum of all channel sample counts)
    // let totalSamples = 0;
    // let samplesCtrBuffer = new Int32Array(channelCountToUse);
    
    // for (let i = 0; i < channelCountToUse; i++) {
    //     let sampleCount = 1; // Default: at least 1 sample per channel for NWB requirement
    //     if (i < bufferedSamplesPerChannel.length && bufferedSamplesPerChannel[i] && bufferedSamplesPerChannel[i].length > 0) {
    //         sampleCount = bufferedSamplesPerChannel[i].length;
    //     }
    //     samplesCtrBuffer[i] = sampleCount;
    //     totalSamples += sampleCount;
    // }

    // if (totalSamples === 0) {
    //     return;
    // }

    // Allocate memory for samples
    bufferedSerialEmptyValue;
    bufferedSerialEmptyCount;
    let totalSamplesCount = 0;
    const visibleCounts = [];
    for (let i = 0; i < totalChannel; i++) {
        if (recordSignalsList && recordSignalsList[i] === 0) continue;
        visibleCounts.push(bufferedSerialEmptyCount[i]);
        totalSamplesCount += bufferedSerialEmptyCount[i];
    }
    let sampledBuffer = new Int16Array(totalSamplesCount);
    let writeOffset = 0;
    for (let i = 0; i < totalChannel; i++) {
        if (recordSignalsList && recordSignalsList[i] === 0) continue;
        const chCount = bufferedSerialEmptyCount[i];
        sampledBuffer.set(
            bufferedSerialEmptyValue[i].subarray(0, chCount),
            writeOffset
        );
        writeOffset += chCount;
    }

    let samplesCtrPtr = NwbModule._malloc(recordChannelCount * NwbModule.HEAP32.BYTES_PER_ELEMENT);
    let samplesCtrPtrStart = samplesCtrPtr / NwbModule.HEAP32.BYTES_PER_ELEMENT;
    let samplesCtrBufferNWB = NwbModule.HEAP32.subarray(samplesCtrPtrStart, (samplesCtrPtrStart + recordChannelCount));
    samplesCtrBufferNWB.set(visibleCounts);

    let samplesPtr = NwbModule._malloc(totalSamplesCount * NwbModule.HEAP16.BYTES_PER_ELEMENT);
    let samplesPtrStart = samplesPtr / NwbModule.HEAP16.BYTES_PER_ELEMENT;
    let samplesBuffer = NwbModule.HEAP16.subarray(samplesPtrStart, (samplesPtrStart + totalSamplesCount));

    // Copy buffered samples sequentially: [visible ch0, visible ch1, ...]
    let segmentIndex = 0;
    for (let i = 0; i < totalChannel; i++) {
        if (recordSignalsList && recordSignalsList[i] === 0) continue;
        let samplesLength = bufferedSerialEmptyCount[i];
        if (i < bufferedSamplesPerChannel.length && bufferedSamplesPerChannel[i] && bufferedSamplesPerChannel[i].length > 0) {
            // Copy actual buffered samples
            const tempArray = bufferedSamplesPerChannel[i];
            samplesBuffer.set(tempArray, segmentIndex);
        } else {
            // Fill with zero sample if channel has no buffered data
            const tempArray = new Int16Array(1);
            samplesBuffer.set(tempArray, segmentIndex);
        }
        segmentIndex += samplesLength;
    }

    // Record the buffered samples (use isRecording = 0 for normal recording, will be set to 1 when finishing)
    NwbModule._nwbfile_add_electrical_series(samplesPtr, samplesCtrPtr, 0, recordChannelCount, 0);
    
    // Free memory
    NwbModule._free(samplesPtr);
    NwbModule._free(samplesCtrPtr);

    // Clear buffers after flushing
    bufferedSamplesPerChannel = [];
    bufferedSampleCounts = [];
}

// called from processing.cpp
function setExpansionBoardType(rawPosExpBoardType, expBoardType){
    
    postMessage({
        "message": "SET_EXPANSION_BOARD_TYPE",
        "expansionBoardType": expBoardType,
    });
    console.log("expansionBoardType", expBoardType);

    // let posExpBoardType = rawPosExpBoardType >> 1;
    // const expBoardTypeBuffer = HEAP16.subarray(posExpBoardType, posExpBoardType + 1);
    // if (previousExpBoardType != expBoardTypeBuffer[0]) {
    //     previousExpBoardType = expBoardTypeBuffer[0];
    //     postMessage({
    //         "message": "SET_EXPANSION_BOARD_TYPE",
    //         "expansionBoardType": expBoardTypeBuffer[0],
    //     });
    //     console.log("setExpansionBoardType : ", previousExpBoardType, expBoardTypeBuffer[0]);
    // }
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

    try {
        const bareName = normalizeNwbFileName(fileName);
        let readData = null;
        for (const path of [bareName, '/' + bareName]) {
            try {
                readData = FS.readFile(path);
                break;
            } catch (_) {}
        }
        if (!readData) {
            throw new Error('NWB not found in MEMFS: ' + bareName);
        }
            if (recordingFileWritable) {
                await recordingFileWritable.write(readData);
                try {
                    console.log("FILENAME:", fileName);
                    FS.unlink('/' + fileName);
                }catch(err) {
                    console.log("UNLINK: ", err);
                }
            }
        // }
    } catch (err) {
        console.error("Error writing to file:", err);
    } finally {
        // Always close the writable, even if there was an error
        if (recordingFileWritable) {
            try {
                await recordingFileWritable.close();
                console.log("recordingFileWritable closed");
            } catch (err) {
                console.error("Error closing writable:", err);
            } finally {
                recordingFileWritable = null; // Prevent double-closing
            }
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

async function seekNwbFileBufferWeb(filePath, outSamples, outSamplesCount, outConfig, startIdx, endIdx, startChannel, endChannel, samplesLength, isStartOpeningFileWeb = false, isPlayback) {
    // SECTION seekNwbFileBufferWeb:  SR_minutes.nwb 5760000 347443 -5412557
    const seekPath = normalizeNwbFileName(filePath);
    console.log("SECTION seekNwbFileBufferWeb: ", seekPath, startIdx, endIdx, samplesLength);
    console.log("isStartOpeningFileWeb: ", isStartOpeningFileWeb);
    // FFI_PLUGIN_EXPORT int32_t nwbfile_seek_electrical_series(const char* path, short* outSamples, int* outSamplesCount, int* outConfig, int startTimeStamp, int endTimeStamp, int startChannel, int endChannel) {
    const result = NwbModule.ccall('nwbfile_seek_electrical_series', 'number', ['string', 'number', 'number', 'number', 'number', 'number', 'number', 'number'], [seekPath, outSamples, outSamplesCount, outConfig, startIdx, endIdx, startChannel, endChannel]);

    if (result == 0) {
        console.log("seekNwbFileBufferWeb success " + result);
    } else {
        console.log("seekNwbFileBufferWeb failed " + result);
        NwbModule._free(outSamples);
        NwbModule._free(outSamplesCount);
        NwbModule._free(outConfig);
        postSeekOpenFailed(isStartOpeningFileWeb, isPlayback);
        return;
    }
    let outConfigStart = outConfig / NwbModule.HEAP32.BYTES_PER_ELEMENT;
    let outConfigBuffer = NwbModule.HEAP32.subarray(outConfigStart, (outConfigStart + 10));

    const tempLoadedChannelCount = outConfigBuffer[1];
    let loadedChannelCount = endChannel - startChannel + 1; // +1 because endChannel is inclusive
    let outSamplesStart = outSamples / NwbModule.HEAP16.BYTES_PER_ELEMENT;
    let outSamplesBuffer = NwbModule.HEAP16.subarray(outSamplesStart, (outSamplesStart + samplesLength * loadedChannelCount));

    let outSamplesCountStart = outSamplesCount / NwbModule.HEAP32.BYTES_PER_ELEMENT;
    let outSamplesCountBuffer = NwbModule.HEAP32.subarray(outSamplesCountStart, (outSamplesCountStart + tempLoadedChannelCount));
    console.log("outSamplesCountBuffer", outSamplesCountBuffer);

    // loadedSamplesBuffer = (outSamplesBuffer).slice();
    // loadedSamplesCountBuffer = (outSamplesCountBuffer).slice();
    // loadedConfigBuffer = (outConfigBuffer).slice();
    loadedSamplesBuffer = (outSamplesBuffer).slice();
    loadedSamplesCountBuffer = (outSamplesCountBuffer).slice();
    if (isStartOpeningFileWeb) {
        loadedConfigBuffer = (outConfigBuffer).slice();
    }
    initWithConfig(loadedConfigBuffer);




    // trigger callback
    if (isPlayback) {
        postMessage({
            message: 'SEEK_NWB_FILE_BUFFER_WEB_CALLBACK_PLAYBACK',
            arrSamples: loadedSamplesBuffer,
            arrSampleCount: loadedSamplesCountBuffer,
            outConfigBuffer: loadedConfigBuffer,
            startIdx: startIdx,
            endIdx: endIdx,
            startChannel: startChannel,
            endChannel: endChannel,
            isStartOpeningFileWeb: isStartOpeningFileWeb,
        });
    } else {
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
    }

    NwbModule._free(outSamples);
    NwbModule._free(outSamplesCount);
    NwbModule._free(outConfig);
}


function initWithConfig(config) {
    let initConfig = config;
    console.log("INIT_WITH_CONFIGZzz: ", initConfig);
    if (!initConfig || initConfig[0] <= 0 || initConfig[1] <= 0) {
        console.error("initWithConfig: invalid config, skipping processing init", initConfig);
        return;
    }
    sampleRate = initConfig[0];
    channelCount = initConfig[1];
    Module._processing_init();
    Module._processing_set_sample_rate(initConfig[0]);
    Module._processing_set_channel_count(initConfig[1]);

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
    let ii = 0;
    drawingCountPtr = Module._malloc(channelCount * Module.HEAP16.BYTES_PER_ELEMENT);
    drawingCountPtrStart = drawingCountPtr / Module.HEAP16.BYTES_PER_ELEMENT;
    drawingCountBuffer = Module.HEAP16.subarray(drawingCountPtrStart, (drawingCountPtrStart + channelCount));
    drawingCountPtrList.push(drawingCountPtr);
    drawingCountBufferList = (drawingCountBuffer);

    console.log("Drawing Count Buffer List: INIT WiTH CONFIG ", channelCount, drawingCountBufferList);
    outEventPositionPtr = Module._malloc(MAX_EVENT_MARKERS * Module.HEAPF64.BYTES_PER_ELEMENT);
    outEventPositionPtrStart = outEventPositionPtr / Module.HEAPF64.BYTES_PER_ELEMENT;
    outEventPositionBuffer = Module.HEAPF64.subarray(outEventPositionPtrStart, (outEventPositionPtrStart + MAX_EVENT_MARKERS));
    for (ii = 0; ii < channelCount; ii++) {
        drawingCountBuffer[ii] = drawSurfaceWidth * 5;
    }

    postMessage({
        "message": "ALLOCATE_DRAWING_DATA_BUFFER",
        "drawingDataBufferList": drawingDataBufferList,
        "drawingCountBufferList": drawingCountBufferList,
        "channelCount": channelCount,
        "eventPositions": outEventPositionBuffer,
    });
}




// function onEventFound(sampleIndex, eventLabel){
//     postMessage({
//         "message": "EVENT_FOUND",
//         "sampleIndex": sampleIndex,
//         "eventLabel": eventLabel,
//     });
// }