#include "myDebug.h"

#define BAUDRATE 250000

#define rx_serial1 21
#define tx_serial1 22

#define DEFAULTSERIAL false
#if DEFAULTSERIAL
#define mySerial_begin(x) Serial.begin(x)
#define mySerial_write(x, y) Serial.write(x, y);
#define mySerial_println(x) Serial.println(x);
#else
#define mySerial_begin(x) Serial1.begin(x, SERIAL_8N1, rx_serial1, tx_serial1)
#define mySerial_write(x, y) Serial1.write(x, y);
#define mySerial_println(x) Serial1.println(x);
#endif

const int sampleRate = 16384;      // Sample rate in Hz
const int frequency = 100;         // Frequency of the sine wave in Hz
const int bufferSize = 2048;       // Number of 16 bit samples in the buffer (reduced size)
const uint16_t amplitude = 32767;  // Amplitude of the sine wave (half of maximum value of 16-bit unsigned integer)

uint16_t buffer[bufferSize] = { 0 };  // Buffer to store the sine wave samples

float n_values[] = { 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1 };

TaskHandle_t uartTaskHandle;
volatile bool toSend = false;

void uartTask(void *parameter) {
  while (1) {
    if (!toSend) {
      toSend = true;
      vTaskDelay(1000);  // Delay for 1 second
    }
  }
}

void setup() {
#if DEFAULTSERIAL
#else
  Serial.begin(BAUDRATE);
#endif
  mySerial_begin(BAUDRATE);

  // Generate the sine wave samples
  for (int i = 0; i < bufferSize; i++) {
    float time = i / (float)sampleRate;
    float angle = frequency * 2 * PI * time;
    int16_t sample = amplitude * sin(angle);
    buffer[i] = map(sample, -amplitude, amplitude, 0, UINT16_MAX);
    buffer[i] = buffer[i] * n_values[(i / (bufferSize / 10))];
    // buffer[i] = i;
  }

  xTaskCreate(uartTask, "UART Task", 2048, NULL, 1, &uartTaskHandle);
}

void loop() {
  if (toSend) {
    toSend = false;

    // for (int i = 0; i < bufferSize; i++) {
    //   mySerial_println(buffer[i]);
    // }

    mySerial_write((uint8_t *)&buffer, bufferSize * 2);
#if DEFAULTSERIAL
#else
    Serial.println("sent data");
#endif
  }
}
