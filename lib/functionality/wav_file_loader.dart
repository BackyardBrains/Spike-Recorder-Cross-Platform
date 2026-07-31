import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:wav/util.dart';
import 'package:wav/wav.dart';
import 'package:wav/wav_format.dart';

/// Reads a WAV file from disk, tolerating Spike Recorder exports whose `data`
/// chunk size in the header does not match the bytes on disk (common for
/// 32-bit float WAV). Falls back to a capped read when [Wav.read] fails.
Future<Wav> readWavFromPath(String filePath) async {
  final bytes = await File(filePath).readAsBytes();
  try {
    return Wav.read(bytes);
  } on FormatException {
    return _readWavTolerant(bytes);
  }
}

/// Same as [Wav.read] but never reads past the end of [bytes].
Wav _readWavTolerant(Uint8List bytes) {
  const kFormatSize = 16;
  const kExCbSize = 22;
  const kPCM = 1;
  const kFloat = 3;
  const kWavExtensible = 65534;
  const kStrRiff = 'RIFF';
  const kStrWave = 'WAVE';
  const kStrFmt = 'fmt ';
  const kStrData = 'data';

  var p = 0;

  String readString(int length) {
    final s = String.fromCharCodes(bytes.sublist(p, p + length));
    p += length;
    return s;
  }

  int readUint16() {
    final v = ByteData.sublistView(bytes, p, p + 2).getUint16(0, Endian.little);
    p += 2;
    return v;
  }

  int readUint24() {
    final b0 = bytes[p++];
    final b1 = bytes[p++];
    final b2 = bytes[p++];
    return b0 + 0x100 * (b1 + 0x100 * b2);
  }

  int readUint32() {
    final v = ByteData.sublistView(bytes, p, p + 4).getUint32(0, Endian.little);
    p += 4;
    return v;
  }

  void skip(int n) {
    p += n;
    if (p > bytes.length) {
      throw FormatException('WAV is corrupted, or not a WAV file.');
    }
  }

  void assertString(String expected) {
    if (readString(expected.length) != expected) {
      throw FormatException('WAV is corrupted, or not a WAV file.');
    }
  }

  bool checkString(String expected) {
    if (p + expected.length > bytes.length) return false;
    final ok = String.fromCharCodes(
            bytes.sublist(p, p + expected.length)) ==
        expected;
    if (ok) p += expected.length;
    return ok;
  }

  void findChunk(String identifier) {
    while (!checkString(identifier)) {
      if (p + 4 > bytes.length) {
        throw FormatException('WAV is missing "$identifier" chunk.');
      }
      final size = readUint32();
      skip(roundUpToEven(size));
    }
  }

  WavFormat getFormat(int formatCode, int bitsPerSample) {
    if (formatCode == kPCM) {
      if (bitsPerSample == 8) return WavFormat.pcm8bit;
      if (bitsPerSample == 16) return WavFormat.pcm16bit;
      if (bitsPerSample == 24) return WavFormat.pcm24bit;
      if (bitsPerSample == 32) return WavFormat.pcm32bit;
    } else if (formatCode == kFloat) {
      if (bitsPerSample == 32) return WavFormat.float32;
      if (bitsPerSample == 64) return WavFormat.float64;
    }
    throw FormatException('Unsupported WAV format: $formatCode, $bitsPerSample');
  }

  double readSample(WavFormat format) {
    switch (format) {
      case WavFormat.pcm8bit:
        return intToSample(bytes[p++], 8);
      case WavFormat.pcm16bit:
        final v = ByteData.sublistView(bytes, p, p + 2)
            .getUint16(0, Endian.little);
        p += 2;
        return intToSample(fold(v, 16), 16);
      case WavFormat.pcm24bit:
        final v = readUint24();
        return intToSample(fold(v, 24), 24);
      case WavFormat.pcm32bit:
        final v = readUint32();
        return intToSample(fold(v, 32), 32);
      case WavFormat.float32:
        final v = ByteData.sublistView(bytes, p, p + 4)
            .getFloat32(0, Endian.little);
        p += 4;
        return v;
      case WavFormat.float64:
        final v = ByteData.sublistView(bytes, p, p + 8)
            .getFloat64(0, Endian.little);
        p += 8;
        return v;
    }
  }

  assertString(kStrRiff);
  readUint32(); // file size
  assertString(kStrWave);
  findChunk(kStrFmt);

  final fmtSize = roundUpToEven(readUint32());
  var formatCode = readUint16();
  final numChannels = readUint16();
  final samplesPerSecond = readUint32();
  readUint32(); // bytes per second
  final bytesPerSampleAllChannels = readUint16();
  final bitsPerSample = readUint16();

  if (formatCode == kWavExtensible) {
    final cbSize = readUint16();
    if (cbSize != kExCbSize) {
      throw FormatException(
        'Extension size of WAVE_FORMAT_EXTENSIBLE should be $kExCbSize',
      );
    }
    final validBitsPerSample = readUint16();
    if (validBitsPerSample != bitsPerSample) {
      throw UnimplementedError(
        'wValidBitsPerSample differs from wBitsPerSample.',
      );
    }
    readUint32(); // channel mask
    formatCode = readUint16();
    skip(14);
  } else if (fmtSize > kFormatSize) {
    skip(fmtSize - kFormatSize);
  }

  findChunk(kStrData);
  final dataSize = readUint32();
  final dataStart = p;
  final bytesAvailable = math.max(0, bytes.length - dataStart);
  final numSamplesFromHeader = dataSize ~/ bytesPerSampleAllChannels;
  final numSamplesFromFile = bytesAvailable ~/ bytesPerSampleAllChannels;
  final numSamples = math.min(numSamplesFromHeader, numSamplesFromFile);

  if (numSamples <= 0 || numChannels <= 0) {
    throw FormatException('WAV has no readable audio samples.');
  }

  final format = getFormat(formatCode, bitsPerSample);
  final channels = List.generate(numChannels, (_) => Float64List(numSamples));

  for (var i = 0; i < numSamples; i++) {
    for (var j = 0; j < numChannels; j++) {
      if (p + (format.bitsPerSample ~/ 8) > bytes.length) {
        return Wav(channels, samplesPerSecond, format);
      }
      channels[j][i] = readSample(format);
    }
  }

  return Wav(channels, samplesPerSecond, format);
}
