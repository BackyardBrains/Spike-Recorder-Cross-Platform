import 'models.dart';

class SerialPortDataModel {
  final String portCom;
  final String deviceDetect;

  SerialPortDataModel({required this.portCom, required this.deviceDetect});
  SerialPortDataModel copyWith({String? portCom, String? deviceDetect}) {
    return SerialPortDataModel(
      portCom: portCom ?? this.portCom,
      deviceDetect: deviceDetect ?? this.deviceDetect,
    );
  }
}

class ComDataWithBoard {
  final SerialPortDataModel serialPortData;
  final Board connectDevices;

  ComDataWithBoard(
      {required this.connectDevices, required this.serialPortData});
}
