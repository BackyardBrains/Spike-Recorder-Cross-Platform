let stateBuffer = null;
let arrStateBuffer = null;
// let receivedBuffer = null;

let sharedBufferWorkerToJS = null;
let sharedBufferViewWorkerToJS = null;
let audioContext;
let audioProcessorNode;
const STATE = {
  'REQUEST_RENDER': 0,
  'IB_FRAMES_AVAILABLE': 1,
  'IB_READ_INDEX': 2,
  'IB_WRITE_INDEX': 3,
  'OB_FRAMES_AVAILABLE': 4,
  'OB_READ_INDEX': 5,
  'OB_WRITE_INDEX': 6,
  'RING_BUFFER_LENGTH': 7,
  'KERNEL_LENGTH': 8,
  'REQUEST_SIGNAL_REFORM': 9,
};

async function getMicSampleRate() {
    const audioTrack = stream.getAudioTracks()[0];
    const trackSettings = audioTrack.getSettings();
    return trackSettings.sampleRate;
}

async function startListeningToMicrophone() {
    if (audioContext !== undefined) {     
        delete audioContext;   
    }
    audioContext = new AudioContext();
    
    let _sampleRate = 44100;
    // Load the audio worklet processor
    await audioContext.audioWorklet.addModule('audio_processor.js');

    console.log("audio_processor.js module loaded");

    audioProcessorNode = new AudioWorkletNode(audioContext, 'my-audio-processor');

    // Setup message event to receive values from the AudioWorkletProcessor
    audioProcessorNode.port.onmessage = (event) => {
        if (event.data.sharedBuffer) {
            console.log("Starting to allocate buffer...");

            stateBuffer = event.data.sharedBuffer;
            arrStateBuffer = new Int16Array(stateBuffer);
            sharedBufferWorkerToJS = event.data.sharedBuffer;
            sharedBufferViewWorkerToJS = new Int16Array(sharedBufferWorkerToJS);
            
            // receivedBuffer = new Int16Array(sharedBufferViewWorkerToJS.length);
            console.log("Buffer allocated in JS ", sharedBufferViewWorkerToJS.length);
            window.onDataBufferAllocated(sharedBufferViewWorkerToJS, 0, _sampleRate);
        } else if (event.data.bufferReady && sharedBufferViewWorkerToJS) {
            // Read samples from the shared buffer when it's ready
            // var date = new Date();
            // console.log("JAVASCRIPT PROCESSED: ", date.getTime())
            // console.log("ON DATA RECEIVED");
            // arrStateBuffer[STATE.IB_FRAMES_AVAILABLE] = ;
            // receivedBuffer.set(sharedBufferViewWorkerToJS);
            window.onDataReceived();
        } else {
            console.log("Message from Audio Processor: ", event.data);
        }
    };

    // Set desired sample rate
    const desiredSampleRate = 44100; // 44.1 kHz

    // Get microphone stream with the desired sample rate
    const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
            sampleRate: desiredSampleRate
        }
    });

    // Get the settings of the audio track
    const audioTrack = stream.getAudioTracks()[0];
    const trackSettings = audioTrack.getSettings();

    // Log the sample rate to the console
    console.log("Microphone sample rate: ", trackSettings.sampleRate);

    const source = audioContext.createMediaStreamSource(stream);

    // Connect source to our processor and then to the context's destination
    source.connect(audioProcessorNode).connect(audioContext.destination);
    _sampleRate = trackSettings.sampleRate;
}
