import 'dart:typed_data';

enum MessageState {
  noSequence,
  inStartSequence,
  inMessage,
}

class MessageIdentifier {
  MessageIdentifier({
    required this.onDeviceData,
    required this.onDeviceMessage,
  });

  final Function(Uint8List) onDeviceData;
  final Function(Uint8List) onDeviceMessage;
  MessageState _messageState = MessageState.noSequence;

  /// 255, 255, 1, 1, 128, 255
  static final Uint8List startSequence = Uint8List.fromList([255, 255, 1, 1, 128, 255]);

  /// 255, 255, 1, 1, 129, 255
  static final Uint8List endSequence = Uint8List.fromList([255, 255, 1, 1, 129, 255]);

  final List<int> _deviceDataBuffer = [];
  final List<int> _messageBuffer = [];
  int _startSequenceFoundIndex = -1;

  void addPacket(Uint8List newPacket) {
    for (int i = 0; i < newPacket.length; i++) {
      switch (_messageState) {
        case MessageState.noSequence:
          if (newPacket[i] == startSequence.first) {
            _startSequenceFoundIndex = 0;
            _messageState = MessageState.inStartSequence;
          } else {
            _deviceDataBuffer.add(newPacket[i]);
          }
          break;

        case MessageState.inStartSequence:
          if (newPacket[i] == startSequence[_startSequenceFoundIndex + 1]) {
            if (_startSequenceFoundIndex == startSequence.length - 2) {
              _messageState = MessageState.inMessage;
            } else {
              _startSequenceFoundIndex++;
            }
          } else {
            // Adding the partial start sequence found to data
            _deviceDataBuffer.addAll(startSequence.sublist(0, _startSequenceFoundIndex + 1));
            _messageState = MessageState.noSequence;
          }
          break;

        case MessageState.inMessage:
          // Contingency if end sequence byte is dropped and
          // all the bytes keep on adding to _messageBuffer
          if (_messageBuffer.length > 50) {
            _messageBuffer.clear();
            _messageState = MessageState.noSequence;
            break;
          }

          // Keep on adding messages / end sequence bytes to _messageBuffer
          _messageBuffer.add(newPacket[i]);

          // When endSequence is found then remove the endSequence from _messageBuffer
          // and send the _messageBuffer
          bool isEndSequenceFound = containsUint8List(_messageBuffer, endSequence);
          if (isEndSequenceFound) {
            removeSublist(_messageBuffer, endSequence);
            onDeviceMessage(Uint8List.fromList(_messageBuffer));
            _messageBuffer.clear();
            _messageState = MessageState.noSequence;
          }
          break;
      }
    }
    if (_messageState != MessageState.noSequence) return;
    if (_deviceDataBuffer.isNotEmpty) {
      onDeviceData(Uint8List.fromList(_deviceDataBuffer));
      _deviceDataBuffer.clear();
    }
  }

  bool containsUint8List(List<int> mainList, List<int> subList) {
    if (mainList.length < subList.length) {
      return false; // The main list is shorter, so it can't contain the sublist.
    }

    for (int i = 0; i <= mainList.length - subList.length; i++) {
      bool found = true;

      for (int j = 0; j < subList.length; j++) {
        if (mainList[i + j] != subList[j]) {
          found = false;
          break;
        }
      }

      if (found) {
        return true; // Sublist found within the main list.
      }
    }

    return false; // Sublist not found within the main list.
  }

  void removeSublist(List<int> mainList, List<int> sublist) {
    for (int i = 0; i <= mainList.length - sublist.length; i++) {
      bool found = true;

      for (int j = 0; j < sublist.length; j++) {
        if (mainList[i + j] != sublist[j]) {
          found = false;
          break;
        }
      }

      if (found) {
        mainList.removeRange(i, i + sublist.length);
        return;
      }
    }
  }
}
