import 'dart:typed_data';


class BitwiseUtil {
  const BitwiseUtil({
    required this.bitCount,
  });

  final int bitCount;

  /// Returns empty list if data has missing bytes
  ///
  /// Bit count is the resolution of data, eg. 16-bit
  /// Human Spikerbox - 14bit data
  /// Human-Human-Interface - 10bit data
  /// Data format - Big endian data is received
  /// 1xxx xxxx - 0xxx xxxx
  Uint8List convertToValue(Uint8List upcomingByte) {
    // To ensure that 16 bit data is received
    if (upcomingByte.length % 2 != 0) return Uint8List.fromList([]);

    for (int k = 0; k < upcomingByte.length; k += 2) {
      List<int> modifiedValue = getCustomValue(upcomingByte.elementAt(k), upcomingByte.elementAt(k + 1));
      upcomingByte.setAll(k, modifiedValue);
    }

    // Read the float values
    // Uint16List bufferView16Bit = upcomingByte.buffer.asUint16List();
    // for (int i = 0; i < bufferView16Bit.length; i++) {
    //   switch (bitCount) {
    //     case 14:
    //       bufferView16Bit[i] = bufferView16Bit[i] - 8192;
    //       break;

    //     case 10:
    //       bufferView16Bit[i] = (bufferView16Bit[i] * 30) - 15360; // (value - 512) * 30
    //       break;

    //     default:
    //       break;
    //   }
    // }
    return upcomingByte;
  }

  /// Returns the value as little endian
  static List<int> getCustomValue(int msb, int lsb) {
    int mMSB = (msb & 0x7f) >> 1; // Shifting the data right
    int modifiedLSB = (lsb & 0x7f) | ((msb & 0x1) << 7) & 0x80; // Dropping the 7th bit and 0th bit//
    return [modifiedLSB, mMSB];
  }
}
