import 'dart:typed_data';

class FrameDetect {
  FrameDetect({
    required this.channelCount,
    this.minimumBytesToCheck,
  }) : _channelBytes = channelCount * 2;

  final int channelCount;
  final int _channelBytes;
  final List<int> _data = List.empty(growable: true);
  final int? minimumBytesToCheck;

  /// Waits for atleast 50 bytes before checking the data for Frame Flag
  Uint8List? addData(Uint8List newData) {
    _data.addAll(newData);
    if(minimumBytesToCheck != null ) if(_data.length < minimumBytesToCheck!) return null;
    return _detectFrameFlag();
  }

  /// Returns data from the index first frame flag is identified
  Uint8List? _detectFrameFlag() {
    int frameFlag = _data.indexWhere((element) => element > 127);
    if(frameFlag == -1) return null;
    int remainingBytesInFrame = (_channelBytes) - 1;
    bool is7thBitLow = false;
    for(int i = 0; i < remainingBytesInFrame; i++) {
      is7thBitLow  =  _data[(frameFlag + 1) + i] < 128;
      if(!is7thBitLow) break;
    }
    if(is7thBitLow) {
      return Uint8List.fromList(_data.sublist(frameFlag));
    }
    return null;
  }
}
