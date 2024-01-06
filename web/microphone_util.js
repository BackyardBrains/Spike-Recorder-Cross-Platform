let sharedBufferWorkerToJS = null;
let sharedBufferViewWorkerToJS = null;
let lastDataReceivedTime = 0;


async function startListeningToMicrophone() {
    const audioContext = new AudioContext();

    // Load the audio worklet processor
    await audioContext.audioWorklet.addModule('audio_processor.js');

    console.log("audio_processor.js module loaded and sample rate" + audioContext.sampleRate);

    const audioProcessorNode = new AudioWorkletNode(audioContext, 'my-audio-processor');

    // Setup message event to receive values from the AudioWorkletProcessor
    audioProcessorNode.port.onmessage = (event) => {
        // console.log("Event length:", event.data ? JSON.stringify(event.data).length : 0);
        // console.log("Event data type:", typeof event.data);
        if (event.data.sharedBuffer) {

            console.log("Starting to allocate buffer...");

            sharedBufferWorkerToJS = event.data.sharedBuffer;
            sharedBufferViewWorkerToJS = new Int16Array(sharedBufferWorkerToJS);

            console.log("Buffer allocated in JS ", sharedBufferViewWorkerToJS.length);
            window.onDataBufferAllocated(sharedBufferViewWorkerToJS);
        } else if (event.data.bufferReady && sharedBufferViewWorkerToJS) {
            // Read samples from the shared buffer when it's ready
            const currentTime = performance.now();
            const interval = currentTime - lastDataReceivedTime;
            console.log("timeTaken : ", interval);
            console.log("Current time : ", currentTime);
            lastDataReceivedTime = currentTime;

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


    console.log("Microphone sample rate: ", trackSettings);
    const source = audioContext.createMediaStreamSource(stream);

    // Connect source to our processor and then to the context's destination
    source.connect(audioProcessorNode).connect(audioContext.destination);
}
