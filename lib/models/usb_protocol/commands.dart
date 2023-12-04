import 'dart:typed_data';

abstract class UsbCommand {
  //message SpikerBox will reply with messages that contain information about hardware type:
  ///this command is for the HHIBOX only
  static const hwTypeInquiry = MessageValueSet(message: 'b');

  /// this command is only for Human spiker Box
  static const hwVersionInquiry = MessageValueSet(message: '?');

  /// received only from human spiker box
  static const eventMessage = MessageValueSet(message: 'EVNT');

  /// this only for human spiker box
  static const deviceConnection = MessageValueSet(message: 'board');

  /// this response is from human spiker box for game controller
  static const joystick = MessageValueSet(message: 'JOY');

  static const List<MessageValueSet> commandList = [
    hwTypeInquiry,
    hwVersionInquiry,
    eventMessage,
    deviceConnection,
  ];

  static String _generatedCommand(
      {required List<MessageValueSet> messageList}) {
    return messageList.map((e) => e.toString()).join(";");
  }

  /// Parse the message received from device
  static List<MessageValueSet> parseCommand({required String cmd}) {
    return cmd
        .split(";")
        .map((e) => MessageValueSet.fromStringCommand(message: e))
        .toList();
  }
}

class MessageValueSet {
  final String message;
  final String value;

  const MessageValueSet({required this.message, this.value = ""});

  factory MessageValueSet.fromStringCommand({required String message}) {
    final List<String> splitString = message.split(':');
    final String msg = splitString.first;
    final String value = splitString.last;
    return MessageValueSet(message: msg, value: value);
  }

  factory MessageValueSet.fromUint8ListCommand({required Uint8List message}) {
    return MessageValueSet.fromStringCommand(
        message: String.fromCharCodes(message));
  }

  @override
  String toString() {
    String generatedCommand = '$message:$value;\n';
    return generatedCommand;
  }

  Uint8List cmdAsBytes() {
    return Uint8List.fromList(toString().codeUnits);
  }
}
