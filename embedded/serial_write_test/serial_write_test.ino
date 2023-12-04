#define BAUDRATE 230400

const uint16_t listLength = 10000;
uint16_t dataList[listLength];

void setup() {
  Serial.begin(BAUDRATE);
  while (!Serial) {}

  for (uint16_t i = 0; i < listLength; i++) {
    dataList[i] = i;
  }
}

void loop() {
  Serial.write((uint8_t*)dataList, listLength * 2);
}
