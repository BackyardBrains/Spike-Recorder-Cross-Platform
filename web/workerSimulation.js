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

/**
 * Flutter web often posts TypedData as `{ o: TypedArray }`. Unwrap to a real
 * typed array so `.length` / `.set` / index access work in the worker.
 */
function unwrapDartTypedArray(value, TypedArrayCtor) {
    if (value == null) return null;
    if (value instanceof TypedArrayCtor) return value;
    if (value.o != null) {
        if (value.o instanceof TypedArrayCtor) return value.o;
        return TypedArrayCtor.from(value.o);
    }
    if (ArrayBuffer.isView(value)) {
        return new TypedArrayCtor(value.buffer, value.byteOffset, Math.floor(value.byteLength / TypedArrayCtor.BYTES_PER_ELEMENT));
    }
    if (Array.isArray(value) || typeof value.length === "number") {
        return TypedArrayCtor.from(value);
    }
    return null;
}

function unwrapInt16(value) {
    return unwrapDartTypedArray(value, Int16Array);
}

function unwrapInt32(value) {
    return unwrapDartTypedArray(value, Int32Array);
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

// Resolved once cprocessing.js's WASM runtime (Module._processing_*) is
// ready. self.onmessage awaits this before touching Module, since the main
// thread doesn't wait for the worker's INITIALIZE_WASM message before
// sending things like INITIALIZE_MICROPHONE.
let isWasmModuleReady = false;
let _resolveWasmModuleReady;
const wasmModuleReadyPromise = new Promise((resolve) => {
    _resolveWasmModuleReady = resolve;
});

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
            if (typeof FS.analyzePath === 'function') {
                const info = FS.analyzePath(path);
                if (info.exists && info.object && !info.object.isFolder) {
                    return bare;
                }
            } else {
                FS.readFile(path);
                return bare;
            }
        } catch (_) {}
    }
    return null;
}

/** Load a disk-picked .nwb into WASM MEMFS so nwbfile_seek_electrical_series can open it. */
async function ensureNwbInMemfs(fileName, fileHandle, options = {}) {
    const bare = normalizeNwbFileName(fileName);
    const existing = nwbExistsInMemfs(bare);
    if (existing) {
        console.log("NWB already in MEMFS:", existing);
        return existing;
    }
    const fromWavConversion = options.fromWavConversion === true;
    const handleIsWav =
        fileHandle &&
        typeof fileHandle.name === 'string' &&
        fileHandle.name.toLowerCase().endsWith('.wav');
    if (fromWavConversion || handleIsWav) {
        console.error(
            "ensureNwbInMemfs: converted NWB missing from MEMFS (will not load .wav as .nwb):",
            bare
        );
        return null;
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

async function prepareNwbFileForOpening(
    fileName,
    fileHandle,
    isStartOpeningFileWeb,
    options = {}
) {
    const skipMemfsReinit = options.skipMemfsReinit === true;
    if (isStartOpeningFileWeb && !skipMemfsReinit) {
        await reinitializeNwbModule();
    }
    return await ensureNwbInMemfs(fileName, fileHandle, {
        fromWavConversion: options.fromWavConversion === true,
    });
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
        isStartOpeningFileWeb,
        {
            skipMemfsReinit: eventFromMain.data.skipMemfsReinit === true,
            fromWavConversion: eventFromMain.data.fromWavConversion === true,
        }
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
    // Capacity passed into WASM is serialPacketLen; after process, counts must be
    // strictly less than capacity. Treating capacity (or serialResult==capacity)
    // as a frame count writes huge mostly-zero slabs and corrupts multi-ch NWB.
    //
    // IMPORTANT: never invent frames from UART byteLength. Human SpikerBox bytes
    // are framed protocol, not raw PCM. A byte-length fallback aged event markers
    // even when 0 samples were decoded → markers drifted off the waveform (#77).
    const isPlausible = (c) => (c | 0) > 0 && (c | 0) < serialPacketLen;

    // Prefer ch0 when serialResult carries a real count (native returns counts[0]).
    let frameCount = isPlausible(serialResult) ? (serialResult | 0) : 0;
    let minPositive = Infinity;
    for (let i = 0; i < totalChannel; i++) {
        const c = outSampleCountsBuffer[i] | 0;
        if (isPlausible(c)) {
            minPositive = Math.min(minPositive, c);
        }
    }
    if (minPositive !== Infinity) {
        // Multi-ch (e.g. HUMANSB 2ch): age/write by the shortest valid channel so
        // markers stay locked to what every channel actually advanced.
        frameCount = frameCount > 0 ? Math.min(frameCount, minPositive) : minPositive;
    }
    // No samples decoded (escape/HWT-only chunk, empty parse) → 0. Callers must
    // not age markers or write NWB for this packet.
    return frameCount > 0 ? frameCount : 0;
}

function buildSerialLiveChunkViews(inSamplesBuffer, outSampleCountsBuffer, totalChannel, serialPacketLen, frameCount) {
    // WASM planar layout: channel i starts at i * serialPacketLen (the capacity
    // passed in out_sample_counts before processing_process_sample_stream).
    const chunkViews = [];
    for (let i = 0; i < totalChannel; i++) {
        let n = outSampleCountsBuffer[i] | 0;
        if (n <= 0 || n >= serialPacketLen) {
            n = frameCount;
        }
        if (n <= 0) continue;
        const start = i * serialPacketLen;
        chunkViews.push(inSamplesBuffer.slice(start, start + n));
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

/// Planar channel layout (NWB / file playback): ch0 block, ch1 block, … with per-channel counts.
function runPlanarSerialThreshold(
    inSamplesPtr,
    inSampleCountsPtr,
    channelCount,
    frameCount,
    eventLabels,
    eventPositions
) {
    if (!isThresholding || frameCount <= 0 || channelCount <= 0) {
        return;
    }

    const thresholdSlotLen = Math.max(
        (drawSurfaceWidth * 5 * 20) | 0,
        (frameCount * 20) | 0
    );

    const outThresholdSamplesPtr = Module._malloc(
        thresholdSlotLen * channelCount * Module.HEAP16.BYTES_PER_ELEMENT
    );
    const outThresholdSampleCountsPtr = Module._malloc(
        channelCount * Module.HEAP32.BYTES_PER_ELEMENT
    );
    const outThresholdSampleCountsPtrStart =
        outThresholdSampleCountsPtr / Module.HEAP32.BYTES_PER_ELEMENT;
    const outThresholdSampleCountsBuffer = Module.HEAP32.subarray(
        outThresholdSampleCountsPtrStart,
        outThresholdSampleCountsPtrStart + channelCount
    );
    outThresholdSampleCountsBuffer.fill(thresholdSlotLen, 0, channelCount);

    const inEventIndicesPtr = Module._malloc(
        eventLabels.length * Module.HEAP32.BYTES_PER_ELEMENT
    );
    const inEventIndicesPtrStart = inEventIndicesPtr / Module.HEAP32.BYTES_PER_ELEMENT;
    const inEventIndicesBuffer = Module.HEAP32.subarray(
        inEventIndicesPtrStart,
        inEventIndicesPtrStart + eventLabels.length
    );
    for (let i = 0; i < eventLabels.length; i++) {
        inEventIndicesBuffer[i] =
            MAX_DISPLAY_SECONDS * sampleRate - eventPositions[i] - frameCount;
    }

    const inEventLabelsPtr = Module._malloc(
        eventLabels.length * Module.HEAP32.BYTES_PER_ELEMENT
    );
    const inEventLabelsPtrStart = inEventLabelsPtr / Module.HEAP32.BYTES_PER_ELEMENT;
    const inEventLabelsBuffer = Module.HEAP32.subarray(
        inEventLabelsPtrStart,
        inEventLabelsPtrStart + eventLabels.length
    );
    inEventLabelsBuffer.set(eventLabels);

    const thresholdResult = Module._processing_process_threshold(
        outThresholdSamplesPtr,
        outThresholdSampleCountsPtr,
        inSamplesPtr,
        inSampleCountsPtr,
        inEventIndicesPtr,
        inEventLabelsPtr,
        eventLabels.length,
        true
    );

    if (thresholdResult === 0) {
        thresholdArrayLength = outThresholdSampleCountsBuffer[0];
        postMessage({
            message: "THRESHOLD_PROCESSED_ARRAY_LENGTH",
            thresholdArrayLength: outThresholdSampleCountsBuffer[0],
        });
    }

    Module._free(outThresholdSamplesPtr);
    Module._free(outThresholdSampleCountsPtr);
    Module._free(inEventIndicesPtr);
    Module._free(inEventLabelsPtr);
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

// High-frequency real-time data messages. If these arrive before the WASM
// module is ready we deliberately DROP them instead of awaiting/queueing
// them - queueing would let a backlog build up in the worker's mailbox and
// then get flushed all at once the moment the module becomes ready, which
// looks like the graph/audio "fast forwarding" through buffered data before
// settling into real-time. Losing a few startup frames is harmless since
// there's nothing on screen yet anyway.
const DROP_IF_WASM_NOT_READY = new Set([
    "INPUT_MICROPHONE_BUFFER",
    "DISPLAY_MICROPHONE_DATA",
    "SEND_SERIAL_DATA_WEB",
    "DISPLAY_SERIAL_DATA_WEB",
    "PROCESS_FFT_MICROPHONE_DATA",
    "PROCESS_PREPARE_FFT_DRAWING",
    "PROCESS_SERIAL_DATA_WEB_RESULT",
]);

var tempOnMessage = self.onmessage;
self.onmessage = async function (eventFromMain) {
    // Guard against the race where the main thread starts sending messages
    // (e.g. INITIALIZE_MICROPHONE) before the cprocessing WASM module has
    // finished loading (self.Module.onRuntimeInitialized below). Without
    // this, calls like Module._processing_init() throw because the exported
    // WASM functions aren't attached yet, silently breaking the whole
    // microphone drawing pipeline (empty graph, no data ever arrives).
    if (!isWasmModuleReady) {
        if (DROP_IF_WASM_NOT_READY.has(eventFromMain.data.message)) {
            return;
        }
        // One-off setup/control messages (INITIALIZE_MICROPHONE, filters,
        // thresholding, file open/save, etc.) are infrequent, so awaiting
        // here just delays them slightly - it never builds up a backlog.
        await wasmModuleReadyPromise;
    }
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
            let r = Module._processing_set_sample_rate(sampleRate);
            Module._processing_set_channel_count(channelCount);
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
                // console.log("RESULT DRAWING: ", resultDrawing, );
                
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


            // Same planar-capacity rule as serial: WASM uses
            // &_out_samples[ch * out_sample_counts[ch]] before overwriting counts.
            for (let i = 0; i < totalChannel; i++) {
                outSampleCountsBuffer[i] = packetLen;
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
                // Write every visible channel (planar [ch0…][ch1…]…), matching the
                // serial recording path. The old code hard-coded channelCount=1 so
                // multi-channel recordings only persisted ch0.
                if (!NwbModule) {
                    console.error("NwbModule not ready for mic recording");
                } else {
                    const writeChannelCount =
                        recordChannelCount > 0 ? recordChannelCount : totalChannel;
                    const frameCount = outSampleCountsBuffer[0] | 0;
                    if (frameCount > 0 && writeChannelCount > 0) {
                        const planar = new Int16Array(writeChannelCount * frameCount);
                        const counts = new Int32Array(writeChannelCount);
                        let recordIdx = 0;
                        let segmentIndex = 0;
                        for (let i = 0; i < totalChannel && recordIdx < writeChannelCount; i++) {
                            if (recordSignalsList && recordSignalsList[i] === 0) continue;
                            const srcStart = i * packetLen;
                            const available = outSampleCountsBuffer[i] | 0;
                            const copyLen = Math.min(
                                frameCount,
                                available > 0 ? available : frameCount,
                                Math.max(0, inSamplesBuffer.length - srcStart)
                            );
                            if (copyLen > 0) {
                                planar.set(
                                    inSamplesBuffer.subarray(srcStart, srcStart + copyLen),
                                    segmentIndex
                                );
                            }
                            counts[recordIdx] = frameCount;
                            recordIdx++;
                            segmentIndex += frameCount;
                        }
                        if (recordIdx === writeChannelCount && segmentIndex > 0) {
                            const samplesPtr = NwbModule._malloc(
                                segmentIndex * NwbModule.HEAP16.BYTES_PER_ELEMENT
                            );
                            const samplesPtrStart =
                                samplesPtr / NwbModule.HEAP16.BYTES_PER_ELEMENT;
                            const samplesBuffer = NwbModule.HEAP16.subarray(
                                samplesPtrStart,
                                samplesPtrStart + segmentIndex
                            );
                            samplesBuffer.set(planar);

                            const samplesCtrPtr = NwbModule._malloc(
                                writeChannelCount * NwbModule.HEAP32.BYTES_PER_ELEMENT
                            );
                            const samplesCtrPtrStart =
                                samplesCtrPtr / NwbModule.HEAP32.BYTES_PER_ELEMENT;
                            const samplesCtrBuffer = NwbModule.HEAP32.subarray(
                                samplesCtrPtrStart,
                                samplesCtrPtrStart + writeChannelCount
                            );
                            samplesCtrBuffer.set(counts);

                            NwbModule._nwbfile_add_electrical_series(
                                samplesPtr,
                                samplesCtrPtr,
                                0,
                                writeChannelCount,
                                0
                            );
                            NwbModule._free(samplesPtr);
                            NwbModule._free(samplesCtrPtr);
                        }
                    }
                }
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

            // WASM sets out_samples[ch] = &_out_samples[ch * out_sample_counts[ch]]
            // BEFORE process overwrites the counts. Capacity must be the planar
            // slot size (serialPacketLen). Using data.length here made ch1+ land
            // at the wrong offset while recording still read i * serialPacketLen
            // — so multi-channel serial NWB files only contained ch0.
            const channelStride = serialPacketLen;
            for (let i = 0; i < totalChannel; i++) {
                outSampleCountsBuffer[i] = channelStride;
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
                    // Write equal-length planar frames every packet.
                    // Planar layout: channel i starts at i * serialPacketLen (WASM
                    // sets out_samples[ch] = &_out_samples[ch * capacity] before
                    // overwriting counts with the real per-channel lengths).
                    if (!NwbModule) {
                        console.error("NwbModule not ready for serial recording");
                    } else if (!recordSignalsList || recordChannelCount <= 0) {
                        console.error("Serial recording mask not initialized");
                    } else {
                        const visibleIndices = [];
                        for (let i = 0; i < totalChannel; i++) {
                            if (recordSignalsList[i] == 0) continue;
                            visibleIndices.push(i);
                        }
                        if (visibleIndices.length === 0) {
                            console.warn("Serial record: no visible channels in mask");
                        } else if (visibleIndices.length !== recordChannelCount) {
                            // Expansion-board / mask drift — writing the wrong
                            // electrode count corrupts the NWB. Skip this packet.
                            console.warn(
                                "Serial record channel mismatch; skip packet",
                                {
                                    visibleIndices: visibleIndices.length,
                                    recordChannelCount,
                                    totalChannel,
                                    mask: Array.from(recordSignalsList),
                                }
                            );
                        } else {
                            const frameCount = resolveSerialFrameCount(
                                serialResult,
                                outSampleCountsBuffer,
                                totalChannel,
                                serialPacketLen,
                                data.length
                            );
                            // Require every visible channel to have a plausible
                            // count for this packet (avoid zero-filling gaps as
                            // fake multi-channel samples).
                            let allChannelsReady = frameCount > 0;
                            for (let vi = 0; vi < visibleIndices.length && allChannelsReady; vi++) {
                                const i = visibleIndices[vi];
                                const available = outSampleCountsBuffer[i] | 0;
                                const usable =
                                    available > 0 && available < channelStride
                                        ? available
                                        : (serialResult > 0 && serialResult < channelStride
                                            ? serialResult
                                            : 0);
                                if (usable < frameCount) {
                                    allChannelsReady = false;
                                }
                            }
                            if (allChannelsReady) {
                                let segmentIndex = 0;
                                const planar = new Int16Array(recordChannelCount * frameCount);
                                const counts = new Int32Array(recordChannelCount);

                                for (let vi = 0; vi < visibleIndices.length; vi++) {
                                    const i = visibleIndices[vi];
                                    const srcStart = i * channelStride;
                                    planar.set(
                                        inSamplesBuffer.subarray(srcStart, srcStart + frameCount),
                                        segmentIndex
                                    );
                                    counts[vi] = frameCount;
                                    segmentIndex += frameCount;
                                }

                                if (segmentIndex > 0) {
                                    const samplesPtr = NwbModule._malloc(
                                        segmentIndex * NwbModule.HEAP16.BYTES_PER_ELEMENT
                                    );
                                    const samplesPtrStart =
                                        samplesPtr / NwbModule.HEAP16.BYTES_PER_ELEMENT;
                                    const samplesBuffer = NwbModule.HEAP16.subarray(
                                        samplesPtrStart,
                                        samplesPtrStart + segmentIndex
                                    );
                                    samplesBuffer.set(planar);

                                    const samplesCtrPtr = NwbModule._malloc(
                                        recordChannelCount * NwbModule.HEAP32.BYTES_PER_ELEMENT
                                    );
                                    const samplesCtrPtrStart =
                                        samplesCtrPtr / NwbModule.HEAP32.BYTES_PER_ELEMENT;
                                    const samplesCtrBuffer = NwbModule.HEAP32.subarray(
                                        samplesCtrPtrStart,
                                        samplesCtrPtrStart + recordChannelCount
                                    );
                                    samplesCtrBuffer.set(counts);

                                    NwbModule._nwbfile_add_electrical_series(
                                        samplesPtr,
                                        samplesCtrPtr,
                                        0,
                                        recordChannelCount,
                                        0
                                    );
                                    NwbModule._free(samplesPtr);
                                    NwbModule._free(samplesCtrPtr);
                                }
                            }
                        }
                    }
                }
                // console.log("PROCESSING THRESHOLD - SEND_SERIAL_DATA_WEB : ", isThresholding);

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
                // Prefer resolved frame count (handles serialResult===0 with valid out counts).
                // Only notify Dart when real samples were inserted — otherwise markers
                // would age with no matching waveform advance (#77).
                const ingestedFrameCount = resolveSerialFrameCount(
                    serialResult,
                    outSampleCountsBuffer,
                    totalChannel,
                    serialPacketLen,
                    data.length
                );
                if (ingestedFrameCount > 0) {
                    postMessage({
                        "message": "SERIAL_DATA_TRANSFER",
                        "frameCount": ingestedFrameCount,
                    });
                }
                
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

                    let nwbFilePath = normalizeNwbFileName(fileHandle.name);
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

                    if (eventFromMain.data.isStartOpeningFileWeb) {
                        console.log(
                            "Opening converted WAV NWB in worker (skip MEMFS reinit):",
                            nwbFilePath
                        );
                        await handleOpenNwbFileWeb(
                            {
                                data: {
                                    filePath: nwbFilePath,
                                    startIdx: eventFromMain.data.startIdx,
                                    endIdx: eventFromMain.data.endIdx,
                                    startChannel: eventFromMain.data.startChannel,
                                    endChannel: eventFromMain.data.endChannel,
                                    isStartOpeningFileWeb: true,
                                    skipMemfsReinit: true,
                                    fromWavConversion: true,
                                },
                            },
                            false
                        );
                    }
                }
                return;
            } else {
                isRecording = 0;

            }


            let nwbSampleRate = eventFromMain.data.sampleRate;
            // Prefer live worker channelCount when Dart still reports 1 after
            // expansion-board discovery (common on serial web).
            let nwbChannelCount = Number(eventFromMain.data.channelCount) || 0;
            if (channelCount > nwbChannelCount) {
                console.warn(
                    "CREATE_NWB_FILE: raising channelCount from Dart",
                    nwbChannelCount,
                    "to live",
                    channelCount
                );
                nwbChannelCount = channelCount;
            }
            if (nwbChannelCount <= 0) {
                nwbChannelCount = channelCount > 0 ? channelCount : 1;
            }
            recordSignalsList = parseVisibleSignalsList(
                eventFromMain.data.visibleSignalsList,
                nwbChannelCount
            );
            // Keep mask aligned with the live processing channel count so
            // SEND_SERIAL_DATA_WEB visibleIndices.length === recordChannelCount.
            const liveChannels = channelCount > 0 ? channelCount : nwbChannelCount;
            if (recordSignalsList.length < liveChannels) {
                const padded = new Int16Array(liveChannels).fill(1);
                padded.set(recordSignalsList);
                recordSignalsList = padded;
            } else if (recordSignalsList.length > liveChannels) {
                recordSignalsList = recordSignalsList.slice(0, liveChannels);
            }
            if (nwbChannelCount < liveChannels) {
                console.warn(
                    "CREATE_NWB_FILE: raising nwbChannelCount to live",
                    nwbChannelCount,
                    "→",
                    liveChannels
                );
                nwbChannelCount = liveChannels;
            }
            // Prefer the mask over Dart's visibleChannelCount — a stale count of 1
            // with a [1,1,…] mask used to create a 1-electrode NWB and drop ch1+.
            let maskVisibleCount = 0;
            for (let i = 0; i < recordSignalsList.length; i++) {
                if (recordSignalsList[i] !== 0) maskVisibleCount++;
            }
            const reportedVisible = Number(eventFromMain.data.visibleChannelCount) || 0;
            recordChannelCount =
                maskVisibleCount > 0
                    ? maskVisibleCount
                    : reportedVisible > 0
                      ? reportedVisible
                      : nwbChannelCount;
            if (reportedVisible > 0 && reportedVisible !== recordChannelCount) {
                console.warn(
                    "CREATE_NWB_FILE visibleChannelCount mismatch; using mask count",
                    reportedVisible,
                    "→",
                    recordChannelCount
                );
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
        case "PROCESS_SERIAL_DATA_WEB_RESULT": {
            const sampleData = unwrapInt16(eventFromMain.data.data);
            const sampleCounts = unwrapInt32(eventFromMain.data.sampleCounts);
            let serialChannelCount = Number(eventFromMain.data.channelCount) | 0;
            const serialEventLabels = JSON.parse(eventFromMain.data.eventLabels);
            const serialEventPositions = JSON.parse(eventFromMain.data.eventPositions);

            if (!sampleData || !sampleCounts || sampleData.length === 0 || sampleCounts.length === 0) {
                console.error("PROCESS_SERIAL_DATA_WEB_RESULT: invalid planar payload", {
                    data: eventFromMain.data.data,
                    counts: eventFromMain.data.sampleCounts,
                    channelCount: serialChannelCount,
                });
                break;
            }
            if (serialChannelCount <= 0) {
                serialChannelCount = sampleCounts.length;
            }
            // Ensure WASM circular buffer has every channel before inject.
            if (serialChannelCount > 0 && channelCount !== serialChannelCount) {
                channelCount = serialChannelCount;
                Module._processing_set_channel_count(serialChannelCount);
            }

            const sampleDataPtr = Module._malloc(sampleData.length * Module.HEAP16.BYTES_PER_ELEMENT);
            const sampleDataPtrStart = sampleDataPtr / Module.HEAP16.BYTES_PER_ELEMENT;
            const sampleDataBuffer = Module.HEAP16.subarray(sampleDataPtrStart, (sampleDataPtrStart + sampleData.length));
            sampleDataBuffer.set(sampleData);

            const sampleCountsPtr = Module._malloc(sampleCounts.length * Module.HEAP32.BYTES_PER_ELEMENT);
            const sampleCountsPtrStart = sampleCountsPtr / Module.HEAP32.BYTES_PER_ELEMENT;
            const sampleCountsBuffer = Module.HEAP32.subarray(sampleCountsPtrStart, (sampleCountsPtrStart + sampleCounts.length));
            sampleCountsBuffer.set(sampleCounts);

            // console.log("PROCESS_SERIAL_DATA_WEB_RESULT inject", {
            //     planarLen: sampleData.length,
            //     counts: Array.from(sampleCounts),
            //     serialChannelCount,
            //     moduleChannelCount: channelCount,
            // });

            const resultSerialInject = Module.ccall(
                'processing_serial_data_result',
                'number',
                ['number', 'number', 'number'],
                [sampleDataPtr, sampleCountsPtr, serialChannelCount]
            );

            const frameCount = sampleCountsBuffer[0] | 0;
            if (resultSerialInject >= 0) {
                runPlanarSerialThreshold(
                    sampleDataPtr,
                    sampleCountsPtr,
                    serialChannelCount,
                    frameCount,
                    serialEventLabels,
                    serialEventPositions
                );
            }

            Module._free(sampleDataPtr);
            Module._free(sampleCountsPtr);
        }
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
        case "ADD_NWB_EVENT": {
            const requestId = eventFromMain.data.requestId;
            if (!NwbModule || typeof NwbModule._nwbfile_add_event !== "function") {
                postMessage({
                    message: "ADD_NWB_EVENT_RESULT",
                    requestId: requestId,
                    rowIndex: -1,
                    error: "NwbModule._nwbfile_add_event unavailable",
                });
                break;
            }
            try {
                const timestampSeconds = Number(eventFromMain.data.timestampSeconds);
                const eventLabel = Number(eventFromMain.data.eventLabel) | 0;
                const rowIndex = NwbModule._nwbfile_add_event(timestampSeconds, eventLabel);
                postMessage({
                    message: "ADD_NWB_EVENT_RESULT",
                    requestId: requestId,
                    rowIndex: rowIndex,
                });
            } catch (err) {
                console.error("ADD_NWB_EVENT error:", err);
                postMessage({
                    message: "ADD_NWB_EVENT_RESULT",
                    requestId: requestId,
                    rowIndex: -1,
                    error: String(err),
                });
            }
        }
        break;
        case "GET_NWB_EVENT_COUNT": {
            const requestId = eventFromMain.data.requestId;
            if (!NwbModule || typeof NwbModule._nwbfile_get_event_count !== "function") {
                postMessage({
                    message: "GET_NWB_EVENT_COUNT_RESULT",
                    requestId: requestId,
                    count: 0,
                    error: "NwbModule._nwbfile_get_event_count unavailable",
                });
                break;
            }
            try {
                const count = NwbModule._nwbfile_get_event_count();
                postMessage({
                    message: "GET_NWB_EVENT_COUNT_RESULT",
                    requestId: requestId,
                    count: count,
                });
            } catch (err) {
                console.error("GET_NWB_EVENT_COUNT error:", err);
                postMessage({
                    message: "GET_NWB_EVENT_COUNT_RESULT",
                    requestId: requestId,
                    count: 0,
                    error: String(err),
                });
            }
        }
        break;
        case "READ_NWB_EVENT": {
            const requestId = eventFromMain.data.requestId;
            if (!NwbModule || typeof NwbModule._nwbfile_read_event !== "function") {
                postMessage({
                    message: "READ_NWB_EVENT_RESULT",
                    requestId: requestId,
                    ok: false,
                    error: "NwbModule._nwbfile_read_event unavailable",
                });
                break;
            }
            let outTimestampPtr = 0;
            let outLabelPtr = 0;
            let outDeletedPtr = 0;
            try {
                const rowIndex = Number(eventFromMain.data.rowIndex) | 0;
                outTimestampPtr = NwbModule._malloc(4);
                outLabelPtr = NwbModule._malloc(4);
                outDeletedPtr = NwbModule._malloc(1);
                const result = NwbModule._nwbfile_read_event(
                    rowIndex,
                    outTimestampPtr,
                    outLabelPtr,
                    outDeletedPtr
                );
                if (result !== 0) {
                    postMessage({
                        message: "READ_NWB_EVENT_RESULT",
                        requestId: requestId,
                        ok: false,
                        error: "nwbfile_read_event returned " + result,
                    });
                } else {
                    const heapView = new DataView(NwbModule.HEAPU8.buffer);
                    const timestampSeconds = heapView.getFloat32(outTimestampPtr, true);
                    const eventLabel = heapView.getInt32(outLabelPtr, true);
                    const deleted = NwbModule.HEAPU8[outDeletedPtr] !== 0;
                    postMessage({
                        message: "READ_NWB_EVENT_RESULT",
                        requestId: requestId,
                        ok: true,
                        timestampSeconds: timestampSeconds,
                        eventLabel: eventLabel,
                        deleted: deleted,
                    });
                }
            } catch (err) {
                console.error("READ_NWB_EVENT error:", err);
                postMessage({
                    message: "READ_NWB_EVENT_RESULT",
                    requestId: requestId,
                    ok: false,
                    error: String(err),
                });
            } finally {
                if (outTimestampPtr) NwbModule._free(outTimestampPtr);
                if (outLabelPtr) NwbModule._free(outLabelPtr);
                if (outDeletedPtr) NwbModule._free(outDeletedPtr);
            }
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

        // Module._processing_* exports are usable now, so let any queued
        // self.onmessage handlers (e.g. INITIALIZE_MICROPHONE) proceed even
        // if NWB Plugin initialization below is still pending/fails.
        isWasmModuleReady = true;
        _resolveWasmModuleReady();
        
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

    // Re-read HEAP views after ccall (memory may have grown during seek).
    let outSamplesCountStart = outSamplesCount / NwbModule.HEAP32.BYTES_PER_ELEMENT;
    let outSamplesCountBuffer = NwbModule.HEAP32.subarray(outSamplesCountStart, (outSamplesCountStart + Math.max(tempLoadedChannelCount | 0, 1)));
    console.log("outSamplesCountBuffer", outSamplesCountBuffer);

    // C++ nwbfile_seek_electrical_series writes samples-per-channel into
    // outSamplesCount[0] only (planar [ch0…][ch1…]…). Native Dart expands that
    // single count to every channel before unpacking; do the same here so
    // scrub/playback don't treat channels > 0 as length 0.
    const samplesPerChannel = outSamplesCountBuffer[0] | 0;
    const countLen = Math.max(loadedChannelCount, tempLoadedChannelCount | 0, 1);
    const expandedCounts = new Int32Array(countLen);
    expandedCounts.fill(samplesPerChannel);

    // Slice the actual written planar payload (not the requested samplesLength,
    // which can be larger than samplesPerChannel near EOF).
    const planarSampleCount = Math.max(samplesPerChannel, 0) * loadedChannelCount;
    let outSamplesStart = outSamples / NwbModule.HEAP16.BYTES_PER_ELEMENT;
    let outSamplesBuffer = NwbModule.HEAP16.subarray(
        outSamplesStart,
        outSamplesStart + planarSampleCount
    );

    // loadedSamplesBuffer = (outSamplesBuffer).slice();
    // loadedSamplesCountBuffer = (outSamplesCountBuffer).slice();
    // loadedConfigBuffer = (outConfigBuffer).slice();
    loadedSamplesBuffer = (outSamplesBuffer).slice();
    loadedSamplesCountBuffer = expandedCounts;
    // Always refresh config from this seek — scrub used to keep a stale
    // loadedConfigBuffer, and a wrong channelCount leaves ch1+ empty after
    // processing_init resets the circular buffer to 1 channel.
    loadedConfigBuffer = Int32Array.from(outConfigBuffer);
    // nwbfile_seek_electrical_series never writes outConfig[7] (draw width),
    // so it is malloc garbage. If we pass that into initWithConfig, drawing
    // buffers are reallocated at the wrong size and the waveform envelope
    // downsampling changes — classic "looks smaller / different after play".
    // Preserve the worker's current sane width (set by mic/serial init or
    // Dart's INIT_WITH_CONFIG with MediaQuery width).
    // if (!(loadedConfigBuffer[7] > 0 && loadedConfigBuffer[7] <= 4096)) {
    //     loadedConfigBuffer[7] = (drawSurfaceWidth > 0 && drawSurfaceWidth <= 4096)
    //         ? drawSurfaceWidth
    //         : 0;
    // }
    console.log("seekNwbFileBufferWeb planar", {
        samplesPerChannel,
        loadedChannelCount,
        planarSampleCount,
        configChannels: loadedConfigBuffer[1],
        drawSurfaceWidth: loadedConfigBuffer[7],
        samplePreviewCh0: loadedSamplesBuffer[0],
        samplePreviewCh1: loadedChannelCount > 1 ? loadedSamplesBuffer[samplesPerChannel] : undefined,
    });
    // Only re-init processing when rate/channels actually change. Re-init on
    // every seek wipes the circular buffer and reallocates drawing buffers,
    // which is what makes play/pause look different from the post-load scrub.
    const seekNeedsReinit =
        sampleRate !== loadedConfigBuffer[0] ||
        channelCount !== loadedConfigBuffer[1] ||
        !Array.isArray(drawingDataPtrList) ||
        drawingDataPtrList.length !== loadedConfigBuffer[1];
    if (seekNeedsReinit) {
        initWithConfig(loadedConfigBuffer);
    } else {
        console.log("seekNwbFileBufferWeb: skip initWithConfig (rate/channels unchanged)", {
            sampleRate,
            channelCount,
            drawSurfaceWidth,
        });
    }




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
    // Dart Int32List often arrives as `{ o: Int32Array }` via postMessage.
    let initConfig = unwrapInt32(config);
    if (!initConfig && config != null && typeof config.length === "number") {
        initConfig = Int32Array.from(config);
    }
    console.log("INIT_WITH_CONFIGZzz: ", initConfig, "raw:", config);
    if (!initConfig || initConfig.length < 2 || initConfig[0] <= 0 || initConfig[1] <= 0) {
        console.error("initWithConfig: invalid config, skipping processing init", initConfig, config);
        return;
    }
    sampleRate = initConfig[0];
    channelCount = initConfig[1];
    // NWB seek only fills outConfig[0..6]. Index 7 (draw width) is often
    // uninitialized malloc garbage. Never adopt it; never replace an already
    // valid width (e.g. 1920 from MediaQuery) with the 800 fallback — that
    // shrinks drawing buffers and makes the waveform look different/smaller.
    // const MAX_DRAW_WIDTH = 4096;
    // if (initConfig[7] > 0 && initConfig[7] <= MAX_DRAW_WIDTH) {
    //     drawSurfaceWidth = initConfig[7];
    // } else if (initConfig[7] > MAX_DRAW_WIDTH) {
    //     console.warn("initWithConfig: ignoring garbage drawSurfaceWidth", initConfig[7], "config=", Array.from(initConfig));
    // }
    // if (!drawSurfaceWidth || drawSurfaceWidth <= 0 || drawSurfaceWidth > MAX_DRAW_WIDTH) {
    //     drawSurfaceWidth = 800;
    // }
    Module._processing_init();
    console.log("INIT_WITH_CONFIG: ", initConfig[0], initConfig);
    Module._processing_set_sample_rate(initConfig[0]);
    const setCh = Module._processing_set_channel_count(initConfig[1]);
    console.log("initWithConfig applied", { sampleRate, channelCount, drawSurfaceWidth, setCh });

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