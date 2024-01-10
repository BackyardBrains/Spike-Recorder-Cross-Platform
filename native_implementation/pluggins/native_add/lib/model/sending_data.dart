import 'dart:typed_data';

class SendingDataToDart {
  final int averageTime;
  final int maxTime;
  final int minTime;
  final Int16List asInt16List;
  SendingDataToDart(
      {required this.asInt16List,
      required this.averageTime,
      required this.maxTime,
      required this.minTime});
}

class PacketAddDetailModel {
  final int averageTime;
  final int maxTime;
  final int minTime;

  PacketAddDetailModel(
      {required this.averageTime,
      required this.maxTime,
      required this.minTime});
}
