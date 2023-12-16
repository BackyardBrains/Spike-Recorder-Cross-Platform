import 'dart:async';
import 'dart:typed_data';

import 'package:spikerbox_architecture/models/models.dart';

import '../../models/global_buffer.dart';
import '../../provider/provider_export.dart';

class DeviceStatusFunctionality {
  final SerialUtil _serialUtil = SerialUtil();
  List<ComDataWithBoard> deviceDataWithCom = [];
  Stream<List<ComDataWithBoard>>? deviceList;
  StreamController<List<ComDataWithBoard>> deviceListStream =
      StreamController();

  bool _isDataIdentified = false;

  Future<void> listenDevice(
    bool dummyDataStatus,
    bool isAudioListen,
    String deviceName,
    int baudRate,
  ) async {
    Stream<Uint8List>? getData =
        await _serialUtil.openPortToListen(deviceName, baudRate);
    listenPort?.cancel();
    try {
      listenPort = getData!.listen((event) {
        if (!dummyDataStatus && !isAudioListen) {
          preEscapeSequenceBuffer.addBytes(event);

          if (_isDataIdentified) {
            // Debugging.printing('us: ${stopwatch.elapsedMicroseconds}, length : ${event.length}');
            // stopwatch.reset();
          } else {
            if (frameDetect != null) {
              return;
            }
            Uint8List? firstFrameData = frameDetect.addData(event);

            if (firstFrameData != null) {
              preEscapeSequenceBuffer.addBytes(firstFrameData);
              _isDataIdentified = true;
            }
          }
        }
      });
    } catch (error) {
      print("the error in Listening is ${error}");
    }
  }

  void connectDeviceList(
      List<String> connectedDevices,
      List<SerialPortDataModel> allDevices,
      SerialDataProvider serialDataProvider) {
    // Create a stream controller to manage the stream

    // Stream<List<ComDataWithBoard>>? deviceList;
    // Call the asynchronous function to get all device lists
    if (connectedDevices.isNotEmpty) {
      SetUpFunctionality().getAllDeviceList().then((value) {
        // Extract the list of boards from the result
        List<Board> allBoards = value.boards ?? [];
        // Filter the boards based on some condition (e.g., matching unique names)
        List<Board> connectedBoards = allBoards.where((board) {
          connectedDevices
              .removeWhere((element) => allDevices.contains(element));

          return connectedDevices.contains(board.uniqueName);
        }).toList();

        allDevices.removeWhere(
            (element) => !connectedDevices.contains(element.deviceDetect));

        deviceDataWithCom =
            createComDataWithBoardList(connectedBoards, allDevices);

        serialDataProvider.setDeviceWithComData(deviceDataWithCom);
      });
    }
  }

  List<ComDataWithBoard> createComDataWithBoardList(
      List<Board> connectedBoards, List<SerialPortDataModel> allDevices) {
    List<ComDataWithBoard> result = [];

    for (SerialPortDataModel device in allDevices) {
      Board matchingBoard = connectedBoards.firstWhere(
        (board) => board.uniqueName == device.deviceDetect,
        orElse: () => Board(
            /* Default values or handle the case when no match is found */),
      );

      ComDataWithBoard comDataWithBoard = ComDataWithBoard(
        connectDevices: matchingBoard,
        serialPortData: device,
      );

      result.add(comDataWithBoard);
    }

    return result;
  }
}
