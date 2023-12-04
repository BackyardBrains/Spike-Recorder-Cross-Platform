#define BAUDRATE 250000
#define rx_serial1 21
#define tx_serial1 22
#define bufferSize 2048 * 2

int previousTime = 0;
int bytesAvailable = 0;

uint16_t ch0[2048];
uint16_t* ch = ch0;


void setup() {
  Serial.begin(BAUDRATE);
  Serial1.begin(BAUDRATE, SERIAL_8N1, rx_serial1, tx_serial1);
  Serial.println("\nSerial setup done");
  previousTime = millis();
}

void loop() {
  while (Serial1.available() == 0) {}
  int newBytesCount = Serial1.available();
  if (newBytesCount % 2 == 0 && newBytesCount >= 32) {
    bytesAvailable += newBytesCount;

    // uint16_t* ch = new uint16_t[newBytesCount / 2];

    Serial1.readBytes((uint8_t*)ch, newBytesCount);
    // uint16_t* ch_buffer = new uint16_t[newBytesCount / 2];
    // memcpy((uint8_t*)ch_buffer, (uint8_t*)ch, newBytesCount);
    // Serial.println("new bytes received: " + String(newBytesCount));
    // for (int i = 0; i < newBytesCount / 2; i++) {
    //   Serial.print(String(ch_buffer[i]) + " , ");
    //   Serial.println(ch_buffer[i], BIN);
    // }
    // delete [] ch_buffer;
    if (bytesAvailable >= bufferSize) {
      int currentTime = millis();
      Serial.println("\n");
      Serial.print("bytesAvailable: " + String(bytesAvailable) + " , ");
      Serial.print("extra bytes: " + String(bytesAvailable - bufferSize) + " , ");
      Serial.print("timestamp(ms): " + String(currentTime) + " , ");
      Serial.println("timeElapsed(ms): " + String(currentTime - previousTime) + "\n\n");
      previousTime = currentTime;
      bytesAvailable = 0;
    }
  }
}
