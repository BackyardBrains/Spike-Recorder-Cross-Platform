import 'dart:typed_data';
import '../models.dart';

class EscapeSequence {
  EscapeSequence({
    this.onDeviceData,
    this.onDeviceMessage,
  });

  final Function(Uint8List)? onDeviceData;
  final Function(Uint8List)? onDeviceMessage;

  /// 255, 255, 1, 1, 128, 255
  static final Uint8List startSequence = Uint8List.fromList([255, 255, 1, 1, 128, 255]);

  /// 255, 255, 1, 1, 129, 255
  static final Uint8List endSequence = Uint8List.fromList([255, 255, 1, 1, 129, 255]);

  SequenceIndexes _startSequenceIndexes = const SequenceIndexes();
  SequenceIndexes _endSequenceIndexes = const SequenceIndexes();
  Uint8List _responseBytes = Uint8List(0);
  Uint8List _messageBuffer = Uint8List.fromList([]);

  /// Adds data to [_responseBytes]
  void _addDataToBuffer(List<int> dataToAdd) {
    // Debugging.printing("Existing buffer: $_responseBytes\nData added to buffer: $dataToAdd");
    _responseBytes = Uint8List.fromList([..._responseBytes, ...dataToAdd]);
  }

  /// Adds data to [_messageBuffer]
  void _addDataToMessageBuffer(List<int> dataToAdd) {
    // Debugging.printing("Existing MESSAGE buffer: $_messageBuffer\nData added to MESSAGE buffer: $dataToAdd");
    _messageBuffer = Uint8List.fromList([..._messageBuffer, ...dataToAdd]);
  }

  void _sendDataAndClearBuffer() {
    if (onDeviceData == null) return;
    if (_responseBytes.isEmpty) return;

    onDeviceData!(_responseBytes);
    _responseBytes = Uint8List.fromList([]);
    _endSequenceIndexes = const SequenceIndexes();
    _startSequenceIndexes = const SequenceIndexes();
  }

  void sendMessageAndClearBuffer() {
    if (onDeviceMessage == null) return;
    if (_messageBuffer.isEmpty) return;
    onDeviceMessage!(_messageBuffer);
    _messageBuffer = Uint8List.fromList([]);
  }

  /// Checks packet for escape sequences
  /// Adds the data to buffer [_responseBytes]
  void addPacket(Uint8List newPacket) {
    if (_startSequenceIndexes.endIndex == -1) {
      // Either start sequence has NOT been found or PARTIALLY found
      _searchStartSequence(newPacket);
    } else {
      // Start sequence has been found
      // End sequence needs to be found
      _searchEndSequence(newPacket, false);
    }
  }

  void _searchStartSequence(Uint8List newPacket) {
    if (_startSequenceIndexes.startIndex == -1) {
      // Check for escape sequence before adding data to buffer
      _startSequenceIndexes = _checkForEscapeSequenceStart(newPacket: newPacket);
      if (_startSequenceIndexes.endIndex != -1) {
        // Entire start sequence is found

        // Add data to message list also
        _addDataToMessageBuffer(newPacket.getRange(_startSequenceIndexes.endIndex + 1, newPacket.length).toList(growable: false));
        // Find the end sequence
        _searchEndSequence(newPacket);
      } else {
        // Add the data to buffer
        _addDataToBuffer(newPacket);

        if (_startSequenceIndexes.startIndex == -1) {
          // No start sequence is found
          // Return the data using callback
          _sendDataAndClearBuffer();
        }
      }
    } else {
      // Check the start of packet for continuing escape sequence
      bool isFoundAtStart = _checkBeginningForSequence(newPacket: newPacket);
      if (isFoundAtStart) {
        // Add data to message list also
        _addDataToMessageBuffer(newPacket.getRange(_startSequenceIndexes.endIndex + 1, newPacket.length).toList(growable: false));

        // Start adding data to response buffer - Including the partial part of start sequence
        _addDataToBuffer(newPacket.toList(growable: false));

        // Find the end sequence
        _searchEndSequence(newPacket);
      } else {
        _startSequenceIndexes = const SequenceIndexes();
        // Search the entire packet for start sequence
        _searchStartSequence(newPacket);
      }
    }
  }

  void _searchEndSequence(Uint8List newPacket, [bool isSamePacket = true]) {
    if (_endSequenceIndexes.startIndex == -1) {
      // Check for end of escape sequence before adding data to buffer
      _endSequenceIndexes = _checkForEscapeSequenceStart(newPacket: newPacket, isStartSequence: false);
      if (_endSequenceIndexes.endIndex != -1) {
        // Entire end sequence found
        // Find the response
        _addDataToBuffer(newPacket);
        Debugging.printing('COMPLETE end sequence found');
        _removeEndSequenceAndAddResponse(newPacket, isSamePacket);
      } else {
        _addDataToBuffer(newPacket);
      }
    } else {
      // Check the start of packet for continuing escape sequence
      bool isFoundAtStart = _checkBeginningForSequence(newPacket: newPacket, isStartSequence: false);
      if (isFoundAtStart) {
        // Entire end sequence found
        // Find the response
        _addDataToBuffer(newPacket);
        Debugging.printing('COMPLETE end sequence found AT beginning');
        Debugging.printing("adding newPacket: $newPacket");
        _adjustBuffersAndCallbacks();
      } else {
        // Remaining part of end sequence NOT found
        _endSequenceIndexes = const SequenceIndexes();
        _addDataToBuffer(newPacket);
        _resetAndCheckRemainingData();
      }
    }
  }

  /// Finds the index of End sequence
  /// Adds message to message buffer
  /// Adds the incoming bytes including data and message to [_responseBytes]
  /// Then removes the messages and sequences from the [_responseBytes]
  /// CALLBACKS - sends message and sends data
  void _removeEndSequenceAndAddResponse(Uint8List bytes, bool isSamePacket) {
    // final Uint8List secondSequences = Uint8List.fromList([255, 255, 1, 1, 129, 255]);
    int matchingIndex = -1;
    int indexTillWhichCheck = bytes.length - endSequence.length;
    for (int i = 0; i <= indexTillWhichCheck; i++) {
      bool match = true;
      for (int j = 0; j < endSequence.length; j++) {
        int a = bytes[i + j];
        int b = endSequence[j];
        if (a != b) {
          match = false;
          break;
        }
      }
      if (match) {
        matchingIndex = i;
        break;
      }
    }

    if (matchingIndex == -1) {
      // Empty the message buffer
      _messageBuffer = Uint8List.fromList([]);
      return;
    }

    if (isSamePacket) {
      // Remove [end sequence +  bytes after that] from Message
      _removeEndSeqAndBytesAfter();
    } else {
      // To be added to message received buffer
      List<int> beforeEndSequence = bytes.sublist(0, matchingIndex);
      _addDataToMessageBuffer(beforeEndSequence);
    }

    // // To be added to response data buffer
    // List<int> afterEndSequence = bytes.sublist(matchingIndex + endSequence.length);
    // addDataToBuffer(afterEndSequence);

    _adjustBuffersAndCallbacks();
  }

  void _adjustBuffersAndCallbacks() {
    removeMessageAndSequencesFromResponseBuffer();

    // Message can be sent through callback but data needs to be checked again for sequence
    sendMessageAndClearBuffer();
    // sendDataAndClearBuffer();

    _resetAndCheckRemainingData();
  }

  void _resetAndCheckRemainingData() {
    // Data buffer needs to be added back as a new packet to check for next starting sequence
    Uint8List dataToRecheck = Uint8List(_responseBytes.length);
    dataToRecheck.setAll(0, _responseBytes);

    _responseBytes = Uint8List.fromList([]);
    _endSequenceIndexes = const SequenceIndexes();
    _startSequenceIndexes = const SequenceIndexes();
    addPacket(dataToRecheck);
  }

  /// Removes start sequence,
  /// Removes message,
  /// Removes end sequence
  removeMessageAndSequencesFromResponseBuffer() {
    List<int> a = _responseBytes.toList();
    List<int> b = [...startSequence, ..._messageBuffer, ...endSequence];

    // Check if 'a' contains 'b'
    int index = -1;
    for (int i = 0; i <= a.length - b.length; i++) {
      if (a[i] == b[0]) {
        bool match = true;
        for (int j = 1; j < b.length; j++) {
          if (a[i + j] != b[j]) {
            match = false;
            break;
          }
        }
        if (match) {
          index = i;
          break;
        }
      }
    }

    // If 'a' contains 'b', remove the first instance of 'b' from 'a'
    if (index != -1) {
      a.removeRange(index, index + b.length);
      _responseBytes = Uint8List.fromList(a);
    }
  }

  /// Searches for end sequence in message buffer,
  /// Removes bytes of end sequence and also the bytes after end sequence
  void _removeEndSeqAndBytesAfter() {
    List<int> a = _messageBuffer.toList();
    List<int> b = endSequence;
    if (a.isEmpty || b.isEmpty || b.length > a.length) {
      return; // 'b' is not present in 'a', or invalid input
    }

    // Check if 'a' contains 'b'
    int index = -1;
    for (int i = 0; i <= a.length - b.length; i++) {
      if (a[i] == b[0]) {
        bool match = true;
        for (int j = 1; j < b.length; j++) {
          if (a[i + j] != b[j]) {
            match = false;
            break;
          }
        }
        if (match) {
          index = i;
          break;
        }
      }
    }

    if (index != -1) {
      a.removeRange(index, a.length);
      _messageBuffer = Uint8List.fromList(a);
    }
  }

  /// isStartSequence - Defines the pattern to be founc
  /// TRUE - uses start sequence pattern
  /// FALSE - uses end sequence pattern
  /// Returns the first sequence start in the packet
  SequenceIndexes _checkForEscapeSequenceStart({required Uint8List newPacket, bool isStartSequence = true}) {
    Uint8List sequenceToFind;
    if (isStartSequence) {
      sequenceToFind = startSequence;
    } else {
      sequenceToFind = endSequence;
    }
    int beginIndex = -1;
    int endIndex = -1;
    int sequenceCharacterIndex = -1;
    List<int> seqFound = [];

    // Checking for sequence start
    outerLoop:
    for (int i = 0; i < newPacket.length; i++) {
      for (int j = 0; j < sequenceToFind.length; j++) {
        if (i + j >= newPacket.length) {
          // break loop if end of packet is reached
          break outerLoop;
        }
        if (newPacket[i + j] != sequenceToFind[j]) {
          // Next character did not match. Resetting the variables.
          beginIndex = -1;
          seqFound.clear();
          break;
        }
        // Adding the characters found
        seqFound.add(sequenceToFind[j]);

        // Only when the first index is found
        if (beginIndex == -1) beginIndex = i + j;

        // Only when the last index is found
        if (j == sequenceToFind.length - 1) {
          endIndex = i + j;
          break outerLoop;
        }
      }
    }

    SequenceIndexes si = SequenceIndexes(
      endIndex: endIndex,
      startIndex: beginIndex,
      sequenceCharacterIndex: sequenceCharacterIndex,
      seqFound: seqFound,
    );

    // Debugging.printing("SequenceIndex in checkForEscapeSequenceStart() : $si");

    return si;
  }

  /// isStartSequence - TRUE - uses start sequence pattern
  /// FALSE - uses end sequence pattern
  bool _checkBeginningForSequence({required Uint8List newPacket, bool isStartSequence = true}) {
    Uint8List sequenceToFind;
    int bytesFound;
    if (isStartSequence) {
      sequenceToFind = startSequence;
      bytesFound = _startSequenceIndexes.seqFound.length;
    } else {
      sequenceToFind = endSequence;
      bytesFound = _endSequenceIndexes.seqFound.length;
    }
    int bytesToMatch = sequenceToFind.length - bytesFound;
    bool remainingFound = true;
    for (int i = 0; i < bytesToMatch; i++) {
      if (newPacket[i] != sequenceToFind[bytesFound + i]) {
        remainingFound = false;
        break;
      }
    }
    if (remainingFound) {
      if (isStartSequence) {
        _startSequenceIndexes = _startSequenceIndexes.copyWith(endIndex: bytesToMatch - 1);
      } else {
        _endSequenceIndexes = _endSequenceIndexes.copyWith(endIndex: bytesToMatch - 1);
      }
    }
    return remainingFound;
  }
}

class SequenceIndexes {
  const SequenceIndexes({
    this.seqFound = const [],
    this.endIndex = -1,
    this.startIndex = -1,
    this.sequenceCharacterIndex = -1,
  });

  final int startIndex;
  final int endIndex;
  final int sequenceCharacterIndex;
  final List<int> seqFound;

  SequenceIndexes copyWith({int? startIndex, int? endIndex, int? sequenceCharacterIndex, List<int>? seqFound}) {
    return SequenceIndexes(
      startIndex: startIndex ?? this.startIndex,
      endIndex: endIndex ?? this.endIndex,
      sequenceCharacterIndex: sequenceCharacterIndex ?? this.sequenceCharacterIndex,
      seqFound: seqFound ?? this.seqFound,
    );
  }

  @override
  String toString() {
    super.toString();
    return "Sequence Indexes: startIndex: $startIndex, endIndex: $endIndex, sequenceCharIndex: $sequenceCharacterIndex, seqFound: $seqFound";
  }
}

// TODO: Remove this test function
/// Function to test Escape Sequence class
void checkEscapeSequence() {
  EscapeSequence escapeSequence = EscapeSequence(
    onDeviceData: (Uint8List devData) {
      Debugging.printing("Device data callback: $devData");
    },
    onDeviceMessage: (Uint8List msg) {
      Debugging.printing("Device message callback: $msg");
    },
  );
  Uint8List bytes0 = Uint8List.fromList(List.generate(10, (index) => 40 + index));
  Uint8List bytes1 = Uint8List.fromList([255, 255, 1, 1, ...List.generate(7, (index) => 50 + index)]);
  Uint8List bytes2 = Uint8List.fromList([255, 255, 1, 1, 128, 255, ...List.generate(11, (index) => 100 + index)]);
  Uint8List bytes3 = Uint8List.fromList([...List.generate(8, (index) => 111 + index), 255, 255, 1, 1, 129, 255, 192, 36, 63, 80, 255, 255, 1, 1, 128, 255, 1, 2, 3, 4, 5, 255, 255, 1]);
  Uint8List bytes4 = Uint8List.fromList([1, 129, 255, 70, 87, 86, 58, 49, 46, 48, 53, 59, 72, 87, 84, 58, 72, 85, 77, 65, 78, 83, 66, 59, 72, 87, 86, 58, 51, 46, 49, 48, 59]);
  List<Uint8List> addedList = [bytes0, bytes1, bytes2, bytes3, bytes4];
  for (int i = 0; i < addedList.length; i++) {
    Debugging.printing("packet added: $i");
    escapeSequence.addPacket(addedList[i]);
    Debugging.printing("\n");
  }
}
