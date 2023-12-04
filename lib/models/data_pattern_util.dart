import 'dart:typed_data';

/// Identifies data is being received by checking
///
/// 1st byte - 7th bit is HIGH
///
/// 2nd byte - 7th bit is LOW
///
/// 3rd byte - 7th bit is LOW
///
/// 4th byte - 7th bit is LOW
class ChannelUtil {

  /// Will receive 4 bytes at a time
  ///
  /// Will identify the number of channels
  static int getChannelCount(Uint8List data) {
    if(data.isEmpty || data.length < 4) return 0;
    Uint8List startingData = data.sublist(0,4);
    int channelCount = 0;
    if(_is2ChPattern(startingData)) return 2;
    if(_is1ChPattern(startingData)) return 1;
    return channelCount;
  }


  static bool _is2ChPattern(List<int> data) {
    // Check if the 7th bit of the first byte is high (1)
    bool is7thBitHigh = (data[0] & 128) != 0;
    bool is7thBitLow = false;
    for(int i = 1; i < 4; i++) {
      // Check if the 7th bit of the second byte is low (0)
      is7thBitLow = (data[i] & 128) == 0;
    }
    return is7thBitHigh && is7thBitLow;
  }

  static bool _is1ChPattern(List<int> data) {
    bool is7thBitHigh = false;
    bool is7thBitLow = false;
    for(int i = 0 ; i < data.length; i+=2) {
      // Check if the 7th bit of the first byte is high (1)
      is7thBitHigh = (data[i] & 128) != 0;

      // Check if the 7th bit of the second byte is low (0)
      is7thBitLow = (data[i + 1] & 128) == 0;
    }
    return is7thBitHigh && is7thBitLow;
  }


  /// Bytes which are more multiple of 4 are dropped
  static Uint8List dropEveryOtherTwoBytes(Uint8List input) {
    int inputLength = input.length;
    int outputLength = inputLength ~/ 2; // Integer division to get half the size

    Uint8List output = Uint8List(outputLength);
    int outputIndex = 0;

    for (int i = 0; i < inputLength; i += 4) {
      // Check if there are at least 2 bytes remaining in the input
      if (i + 1 < inputLength) {
        output[outputIndex++] = input[i];
        output[outputIndex++] = input[i + 1];
      }
    }

    return output;
  }
}