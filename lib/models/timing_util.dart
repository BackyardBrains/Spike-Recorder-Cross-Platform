import 'dart:typed_data';

class TimingUtil {
  List<Uint8List> packets = [];
  Stopwatch stopwatch = Stopwatch();
  int totalTimeElapsed = 0;
  Uint8List carryForward = Uint8List(0);

  Uint8List getAllData() {
    Uint8List combinedData = packets.fold(
        carryForward,
        (previousList, currentList) =>
            Uint8List.fromList([...previousList, ...currentList]));
    // if (carryForward.isNotEmpty) carryForward = Uint8List(0);
    // int combinedLength = combinedData.length;
    // if (combinedLength % 2 != 0) {
    //   carryForward = Uint8List.fromList([combinedData.last]);
    //   print("combined data length : $combinedLength, carryForward length: ${carryForward.length}");
    //   return combinedData.sublist(0, combinedLength - 1);
    // }
    // print("combined data length : $combinedLength, carryForward length: ${carryForward.length}");
    return combinedData;
  }

  void addPacket(Uint8List packet) {
    if (!stopwatch.isRunning) {
      stopwatch.start();
    }
    packets.add(packet);
  }

  int getTotalPacketsReceived() {
    return packets.length;
  }

  int getTotalBytesReceived() {
    int totalBytes = 0;
    for (var packet in packets) {
      totalBytes += packet.length;
    }
    return totalBytes;
  }

  double getAveragePacketLength() {
    if (packets.isEmpty) {
      return 0;
    }

    int totalLength = 0;
    for (var packet in packets) {
      totalLength += packet.length;
    }
    return totalLength / packets.length;
  }

  int getMinimumPacketSize() {
    if (packets.isEmpty) {
      return 0;
    }

    int minSize = packets[0].length;
    for (var packet in packets) {
      if (packet.length < minSize) {
        minSize = packet.length;
      }
    }
    return minSize;
  }

  int getMaximumPacketSize() {
    if (packets.isEmpty) {
      return 0;
    }

    int maxSize = packets[0].length;
    for (var packet in packets) {
      if (packet.length > maxSize) {
        maxSize = packet.length;
      }
    }
    return maxSize;
  }

  void printStatistics() {
    if (stopwatch.isRunning) {
      print(
          "Total Time Elapsed: ${stopwatch.elapsedMicroseconds} us, ${stopwatch.elapsedMilliseconds} ms, ${stopwatch.elapsedMilliseconds / 1000} s");
    }
    int totalPackets = getTotalPacketsReceived();
    int totalBytes = getTotalBytesReceived();
    double avgPacketLength = getAveragePacketLength();
    int minPacketSize = getMinimumPacketSize();
    int maxPacketSize = getMaximumPacketSize();

    print("Total Packets Received: $totalPackets");
    print("Total Bytes Received: $totalBytes");
    print("Average Packet Length: $avgPacketLength");
    print("Minimum Packet Size: $minPacketSize");
    print("Maximum Packet Size: $maxPacketSize");
    print("\n");
  }

  void reset() {
    packets.clear();
    stopwatch.stop();
    stopwatch.reset();
    stopwatch.start();
  }
}
