const SAMPLE_BUFFER_SIZE = 2048;

class MyAudioProcessor extends AudioWorkletProcessor {
    constructor() {
        super();

        // Create a SharedArrayBuffer to store samples
        this.sharedBuffer = new SharedArrayBuffer(SAMPLE_BUFFER_SIZE * Int16Array.BYTES_PER_ELEMENT);
        this.sampleBuffer = new Int16Array(this.sharedBuffer);
        this.sampleIndex = 0;

        // Notify the main thread about the shared buffer immediately after creation
        this.port.postMessage({ sharedBuffer: this.sharedBuffer });
    }

    process(inputs, outputs, parameters) {
        const input = inputs[0];

        // Check for valid audio data before accessing it
        if (input && input.length > 0) {
            for (let sample of input[0]) {
                let int16Value = Math.round(this.floatToInt16(sample));
                this.sampleBuffer[this.sampleIndex] = int16Value;
                this.sampleIndex++;

                // If buffer is full, notify the main thread
                if (this.sampleIndex === SAMPLE_BUFFER_SIZE) {
                    this.sampleIndex = 0; // Reset index
                    this.port.postMessage({ bufferReady: true });
                }
            }
        } else {
            this.port.postMessage("No audio data available");
        }

        // For now, just copying input to output to ensure continuous audio processing
        // for (let channel = 0; channel < input.length; channel++) {
        //     const inputChannel = input[channel];
        //     const outputChannel = outputs[0][channel];
        //     for (let i = 0; i < inputChannel.length; i++) {
        //         outputChannel[i] = inputChannel[i];
        //     }
        // }

        return true;
    }

    floatToInt16(sampleValue) {
        // Clamp the value to ensure it's within the valid range
        const clampedValue = Math.max(-1, Math.min(1, sampleValue));

        // Convert to Int16 range
        return clampedValue < 0 ? clampedValue * 32768 : clampedValue * 32767;
    }
}

registerProcessor('my-audio-processor', MyAudioProcessor);
