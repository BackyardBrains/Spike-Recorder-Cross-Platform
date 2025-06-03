import 'package:flutter/foundation.dart';

screenPositionToElementPosition(
    posX,
    // level,
    int sampleRate,
    int cBuffIdx,
    double displayTimeMs,
    double displayTimeWidth,
    double surfaceWidth,
    List<double> res) {
  int tail = cBuffIdx;

  // int prevSegment = (envelopeSize / divider).floor();
  
  double screenMs = displayTimeMs * surfaceWidth / displayTimeWidth;
  double totalSamplesScreen = screenMs * sampleRate;
  double samplesPerPixel = totalSamplesScreen / surfaceWidth;
  // if (kIsWeb) {
  //   samplesPerPixel = samplesPerPixel / 2;
  // }

  double samplePosX = (surfaceWidth - posX) * samplesPerPixel;
  res[0] = 0;
  res[1] = totalSamplesScreen;
  print("SCREEN MS : $screenMs $totalSamplesScreen $samplesPerPixel");
  print("samplePosX  $samplePosX $surfaceWidth $totalSamplesScreen | SREENMS $screenMs $sampleRate | $displayTimeMs $surfaceWidth $displayTimeWidth");
  return samplePosX;
  /*
    Division left right & skipCount
  */
  // int division = 2;
  // int elementLength = ((surfaceWidth - posX) * samplesPerPixel ).floor();

  double curStart = (tail - totalSamplesScreen);
  print("curStart :  $curStart => $tail - $totalSamplesScreen");
  // if (isThreshold) {
  //   if (divider == 6) {
  //     curStart = (maxEnvelopeSize / 2 / divider / 2).floor();
  //   } else {
  //     curStart = ((posX) * samplesPerPixel / division * skipCount).floor();
  //     curStart = (curStart).floor();
  //   }
  // } else {
  // }
  if (curStart < 0) {
    curStart = 0;
  }
  print("cBuffIdx : $curStart $screenMs==> $displayTimeMs * $surfaceWidth / $displayTimeWidth ${totalSamplesScreen.floor()} $cBuffIdx = $displayTimeMs $surfaceWidth $displayTimeWidth");
  res.clear();
  res.add(curStart);
  res.add(curStart + totalSamplesScreen);
  return curStart;
}



int calculateLevel(double timescale, double sampleRate, double windowWidth, List<int> arrCounts, int incSkip) {
  double rawPocket = timescale * sampleRate / windowWidth / 1000;
  int currentLevel = arrCounts.length - 1;
  int i = arrCounts.length - 2;

  if (rawPocket.floor() < 4) {
    currentLevel = -1;
  } else {
    for (; i >= 0; i--) {
      if (arrCounts[i + 1] >= rawPocket && arrCounts[i] < rawPocket) {
        currentLevel = i + 1;
      }
    }
    currentLevel = currentLevel + incSkip;
    if (currentLevel > arrCounts.length - 1) {
      currentLevel = arrCounts.length - 1;
    }
  }

  return currentLevel;
}