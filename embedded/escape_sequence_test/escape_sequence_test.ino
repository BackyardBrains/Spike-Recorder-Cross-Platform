uint8_t data[] = { 255, 255, 1, 1, 128, 255, 1, 2, 3, 4, 5, 255, 255, 1, 1, 129, 255 };

void setup() {
  Serial.begin(500000);  // Initialize Serial communication
}

void loop() {
  Serial.write((const uint8_t*)data, 17);
  delay(1000);       
}