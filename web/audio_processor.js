const SAMPLE_BUFFER_SIZE = 2048 / 4;
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
let STATE_LENGTH = Object.keys(STATE).length;
let max = Math.max;
let min = Math.min;

class MyAudioProcessor extends AudioWorkletProcessor {
    constructor() {
        super();

        // Create a SharedArrayBuffer to store samples
        this.readingIdx = 0;
        this.incliner = 0;
        this.arrProcessorState = new Int32Array(STATE_LENGTH);
        this.arrProcessorState[STATE.IB_READ_INDEX] = 0;
        this.arrProcessorState[STATE.IB_WRITE_INDEX] = 0;
        this.arrProcessorState[STATE.RING_BUFFER_LENGTH] = SAMPLE_BUFFER_SIZE * 5;

        this.sabCircularBuffer = new SharedArrayBuffer(this.arrProcessorState[STATE.RING_BUFFER_LENGTH] * Int16Array.BYTES_PER_ELEMENT);
        this.arrCircularBuffer = new Int16Array(this.sabCircularBuffer);

        this.sharedBuffer = new SharedArrayBuffer(SAMPLE_BUFFER_SIZE * Int16Array.BYTES_PER_ELEMENT);
        this.sampleBuffer = new Int16Array(this.sharedBuffer);
        this.sampleIndex = 0;

        // Notify the main thread about the shared buffer immediately after creation
        // this.port.postMessage({ sharedBuffer: this.sharedBuffer });
        this.port.postMessage({ sharedBuffer: this.sharedBuffer, stateBuffer: this.sabCircularBuffer });
    }

    _pushInputChannelData(channelIdx, inputChannelData) {
        let inputWriteIndex = this.arrProcessorState[STATE.IB_WRITE_INDEX];

        if (inputWriteIndex + inputChannelData.length < this.arrProcessorState[STATE.RING_BUFFER_LENGTH]) {
            this.arrCircularBuffer.set(inputChannelData, inputWriteIndex);
            this.arrProcessorState[STATE.IB_WRITE_INDEX] += inputChannelData.length;
        } else {
            // When the ring buffer does not have enough space so the index needs to
            // be wrapped around.
            let splitIndex = this.arrProcessorState[STATE.RING_BUFFER_LENGTH] - inputWriteIndex;
            let firstHalf = inputChannelData.subarray(0, splitIndex);
            let secondHalf = inputChannelData.subarray(splitIndex);
            this.arrCircularBuffer.set(secondHalf);
            this.arrCircularBuffer.set(firstHalf, inputWriteIndex);
            this.arrProcessorState[STATE.IB_WRITE_INDEX] = secondHalf.length;
        }

        // Update the number of available frames in the input ring buffer.
        // this.arrProcessorState[STATE.IB_FRAMES_AVAILABLE] += inputChannelData.length;
    }

    _pullOutputChannelData(channelIdx, outputChannelData) {
        const outputReadIndex = this.arrProcessorState[STATE.OB_READ_INDEX];
        const nextReadIndex = outputReadIndex + outputChannelData.length;

        if (nextReadIndex < this.arrProcessorState[STATE.RING_BUFFER_LENGTH]) {
            outputChannelData.set(
                this.arrCircularBuffer.subarray(outputReadIndex, nextReadIndex));
            // console.log("outputChannelData.length: ", outputChannelData.length);
            this.arrProcessorState[STATE.OB_READ_INDEX] += outputChannelData.length;
        } else {
            let overflow = nextReadIndex - this.arrProcessorState[STATE.RING_BUFFER_LENGTH];
            let firstHalf = this.arrCircularBuffer.subarray(outputReadIndex);
            let secondHalf = this.arrCircularBuffer.subarray(0, overflow);
            outputChannelData.set(firstHalf);
            outputChannelData.set(secondHalf, firstHalf.length);
            this.arrProcessorState[STATE.OB_READ_INDEX] = secondHalf.length;
        }
    }    

    process(inputs, outputs, parameters) {
        const input = inputs[0];
        const MAX_INT16 = 32767;
        // Check for valid audio data before accessing it
        if (input && input.length > 0) {
            // console.log("LENGTH : ", input[0].length);
            let n = input[0].length;
            let resamples = new Int16Array(n);
            let i = n-1;
            let s = 1 ;
            for (;i>=0;i--){
                // s = max(-1, min(1, input[0][i]));
                // resamples[i] = (s < 0 ? s * 0x8000 : s * 0x7FFF);
                const scaledSample = input[0][i] * MAX_INT16;
                const clampedSample = Math.max(-MAX_INT16 - 1, Math.min(MAX_INT16, scaledSample));
                resamples[i] = clampedSample;
            }
            // this.incliner += 3;
            // if (this.incliner >= 200) {
            //     this.incliner = 0;
            // }
            this._pushInputChannelData(0, resamples);
            
            this.readingIdx = (this.readingIdx + n);
            if (this.readingIdx >= SAMPLE_BUFFER_SIZE) {
                this.readingIdx = 0;
                // console.log("this.sampleBuffer1: ", this.readingIdx, this.arrProcessorState[STATE.OB_READ_INDEX], this.arrProcessorState[STATE.IB_WRITE_INDEX], this.arrProcessorState[STATE.RING_BUFFER_LENGTH]);
                this._pullOutputChannelData(0, this.sampleBuffer);
                this.port.postMessage({ bufferReady: true });
            }
            // let readingIdx = this.arrProcessorState[STATE.IB_READING_INDEX];
            // let clampedIdx = readingIdx;

            // // console.log("Count: ", this.sampleIndex, this.arrProcessorState[STATE.IB_FRAMES_AVAILABLE],);

            //     // this.sampleIndex += input[0].length;
            //     clampedIdx = (readingIdx + input[0].length) % this.arrProcessorState[STATE.RING_BUFFER_LENGTH];
            //     this.sampleBuffer[i] = Math.round(this.floatToInt16(this.arrCircularBuffer[clampedIdx]));
            //     this.arrProcessorState[STATE.IB_READING_INDEX]++;
            //     if (this.sampleIndex == SAMPLE_BUFFER_SIZE) {
            //         this.sampleIndex = 0; // Reset index
            //         this.arrProcessorState[STATE.IB_FRAMES_AVAILABLE] -= SAMPLE_BUFFER_SIZE;
            //     }

            // let writingIdx = this.arrProcessorState[STATE.IB_WRITE_INDEX];
            // let clampedIdx = 0;
            // for (let i = 0; i < input[0].length; i++) { 
            //     let sample = input[0][i];
            //     let int16Value = Math.round(this.floatToInt16(sample));
            //     clampedIdx = (writingIdx + i) % this.arrProcessorState[STATE.RING_BUFFER_LENGTH];
            //     // console.log("clampedIdx");
            //     // console.log(clampedIdx);
            //     this.arrCircularBuffer[clampedIdx] = int16Value;
            //     this.sampleIndex++;
            //     if (this.sampleIndex === SAMPLE_BUFFER_SIZE) {
            //         let startIdx = this.arrProcessorState[STATE.IB_READ_INDEX];
            //         this.sampleIndex = 0; // Reset index
            //         for (let i = 0; i < SAMPLE_BUFFER_SIZE; i++) { 
            //             this.sampleBuffer[i] = this.arrCircularBuffer[startIdx + i];
            //         }
            //         this.arrProcessorState[STATE.IB_READ_INDEX] = startIdx + SAMPLE_BUFFER_SIZE;
            //         // console.log("this.sampleBuffer");
            //         // console.log(this.sampleBuffer);
            //         this.port.postMessage({ bufferReady: true });
            //     }

            // }


            // for (let sample of input[0]) {
            //     let int16Value = Math.round(this.floatToInt16(sample));

            //     this.sampleBuffer[this.sampleIndex] = int16Value;
            //     this.sampleIndex++;

            //     // If buffer is full, notify the main thread
            //     if (this.sampleIndex === SAMPLE_BUFFER_SIZE) {
            //         this.sampleIndex = 0; // Reset index
            //         // var date = new Date();
            //         // console.log("JAVASCRIPT DATA RECEIVED: ", date.getTime())
            //         this.port.postMessage({ bufferReady: true });
            //     }
            // }
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
        // const roundedValue = Math.round(sampleValue);
        // return Math.max(-32768, Math.min(32767, roundedValue));        
        // // Clamp the value to ensure it's within the valid range
        // const clampedValue = Math.max(-1, Math.min(1, sampleValue));

        // // // Convert to Int16 range
        // return clampedValue < 0 ? clampedValue * 32768 : clampedValue * 32767;

        let s = Math.max(-1, Math.min(1, sampleValue));
        return s < 0 ? s * 0x8000 : s * 0x7FFF;
    }
}

registerProcessor('my-audio-processor', MyAudioProcessor);
