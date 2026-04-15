let stateBuffer = null;
let arrStateBuffer = null;
// let receivedBuffer = null;

let sharedBufferWorkerToJS = null;
let sharedBufferViewWorkerToJS = null;
let audioContext;
let audioProcessorNode;
let mediaStream;
let mediaStreamSource;
let isInitializing = false;
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
    if (mediaStream) {
        const audioTrack = mediaStream.getAudioTracks()[0];
        const trackSettings = audioTrack.getSettings();
        console.log("MEDIA STREAM SAMPLE RATE: ${trackSettings.sampleRate}");
        if (trackSettings.sampleRate !== undefined) return trackSettings.sampleRate;
        else {
            const tempContext = new (window.AudioContext || window.webkitAudioContext)();
            const rate = tempContext.sampleRate;        
            await tempContext.close();
            console.log("MEDIA CONTEXT: ${rate}");
            return rate;
    
        }

    } else {
        console.log("MEDIA CONTEXT: ${rate}");
        const tempContext = new (window.AudioContext || window.webkitAudioContext)();
        const rate = tempContext.sampleRate;        
        console.log("MEDIA CONTEXT: ${rate}", rate);
        await tempContext.close();
        return rate;
    }
    return null;
}

function cleanupAudioResources() {
    console.log("Cleaning up audio resources...");
    
    // Disconnect and remove event listener from audio processor node
    if (audioProcessorNode) {
        try {
            audioProcessorNode.port.onmessage = null;
            audioProcessorNode.disconnect();
        } catch (err) {
            console.log("Error disconnecting audioProcessorNode:", err);
        }
        audioProcessorNode = null;
    }
    
    // Disconnect media stream source
    if (mediaStreamSource) {
        try {
            mediaStreamSource.disconnect();
        } catch (err) {
            console.log("Error disconnecting mediaStreamSource:", err);
        }
        mediaStreamSource = null;
    }
    
    // Stop all tracks in the media stream
    if (mediaStream) {
        try {
            mediaStream.getTracks().forEach(track => {
                track.stop();
                console.log("Stopped media track:", track.kind);
            });
        } catch (err) {
            console.log("Error stopping media stream tracks:", err);
        }
        mediaStream = null;
    }
    
    // Close audio context
    if (audioContext) {
        try {
            if (audioContext.state !== 'closed') {
                audioContext.close().then(() => {
                    console.log("AudioContext closed successfully");
                }).catch(err => {
                    console.log("Error closing AudioContext:", err);
                });
            }
        } catch (err) {
            console.log("Error closing AudioContext:", err);
        }
        audioContext = null;
    }
}

async function startListeningToMicrophone(sampleRate) {
    // Prevent multiple simultaneous initializations
    if (isInitializing) {
        console.log("startListeningToMicrophone already in progress, skipping...");
        return;
    }
    
    isInitializing = true;
    
    try {
        // Clean up existing resources first
        cleanupAudioResources();
        
        // Wait a bit for cleanup to complete
        await new Promise(resolve => setTimeout(resolve, 100));
        
        // Create new AudioContext
        audioContext = new AudioContext();
        console.log("Created new AudioContext");
        
        let _sampleRate = sampleRate;
        
        // Load the audio worklet processor
        await audioContext.audioWorklet.addModule('audio_processor.js');
        console.log("audio_processor.js module loaded");

        // Create new audio processor node
        audioProcessorNode = new AudioWorkletNode(audioContext, 'my-audio-processor');

        // Setup message event to receive values from the AudioWorkletProcessor
        audioProcessorNode.port.onmessage = (event) => {
            if (event.data.sharedBuffer) {
                console.log("Starting to allocate buffer...");

                stateBuffer = event.data.sharedBuffer;
                arrStateBuffer = new Int16Array(stateBuffer);
                sharedBufferWorkerToJS = event.data.sharedBuffer;
                sharedBufferViewWorkerToJS = new Int16Array(sharedBufferWorkerToJS);
                
                console.log("Buffer allocated in JS ", sharedBufferViewWorkerToJS.length, "SAMPLE RATE: ", _sampleRate);
                window.onDataBufferAllocated(sharedBufferViewWorkerToJS, 0, _sampleRate);
            } else if (event.data.bufferReady && sharedBufferViewWorkerToJS) {
                // Read samples from the shared buffer when it's ready
                if (window.onDataReceived && typeof window.onDataReceived === 'function') {
                    try {
                        window.onDataReceived();
                    } catch (error) {
                        console.error("Error calling onDataReceived:", error);
                    }
                } else {
                    console.warn("onDataReceived is not available or not a function");
                }
            } else {
                console.log("Message from Audio Processor: ", event.data);
            }
        };

        // Set desired sample rate
        const desiredSampleRate = 44100; // 44.1 kHz

        // Get microphone stream with the desired sample rate
        mediaStream = await navigator.mediaDevices.getUserMedia({
            audio: {
                sampleRate: desiredSampleRate
            }
        });

        // Get the settings of the audio track
        if (mediaStream !== undefined) {
            console.log("MEDIA STREAM zzz2: ${mediaStream}", mediaStream.getAudioTracks()[0]);
            const audioTrack = mediaStream.getAudioTracks()[0];
            const trackSettings = audioTrack.getSettings();
            console.log("MEDIA SETTINGS zzz1: ${mediaStream}", trackSettings.sampleRate);
    
            // Log the sample rate to the console
            if (trackSettings.sampleRate !== undefined) {
                console.log("Microphone sample rate: ", trackSettings.sampleRate);
                _sampleRate = trackSettings.sampleRate;
            } else {
                console.log("MEDIA SAMPLE RATE: ${mediaStream} 000");
                _sampleRate = await getMicSampleRate();
                console.log("MEDIA SAMPLE RATE: ${mediaStream}", _sampleRate);
            }
        } else {
            _sampleRate = await getMicSampleRate();
        }

        // Create media stream source
        mediaStreamSource = audioContext.createMediaStreamSource(mediaStream);

        // Connect source to our processor and then to the context's destination
        mediaStreamSource.connect(audioProcessorNode).connect(audioContext.destination);
        
        console.log("Microphone listening started successfully");
    } catch (error) {
        console.error("Error in startListeningToMicrophone:", error);
        // Clean up on error
        cleanupAudioResources();
    } finally {
        isInitializing = false;
    }
}
