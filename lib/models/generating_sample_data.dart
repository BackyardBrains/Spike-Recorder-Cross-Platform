import 'dart:math' as math;
import 'dart:typed_data';

abstract class GenerateSampleData {
  /// [frequencies] list of frequencies to be included in the signal
  static List<double> sineWaveDouble({required int samplingRate, required List<int> frequencies, int samplesGenerated = 4096}) {
    List<double> wave = List.generate(samplesGenerated, (index) => 0, growable: false);

    for (int k = 0; k < frequencies.length; k++) {
      for (int i = 0; i < samplesGenerated; i++) {
        double hz_1 = (math.sin((2 * 3.14159265358979323846264338328) * frequencies[k] * i / samplingRate));
        wave[i] += hz_1;
      }
    }
    return wave;
  }

  static Uint16List sineWaveUint16({required int samplingRate, required List<int> frequencies, int samplesGenerated = 4096}) {
    return doubleListToUint16List(sineWaveDouble(
      samplingRate: samplingRate,
      frequencies: frequencies,
      samplesGenerated: samplesGenerated,
    ));
  }

  static Uint16List sineWaveUint14({required int samplingRate, required List<int> frequencies, int samplesGenerated = 4096}) {
    return scaleUint16ListTo14Bit(sineWaveUint16(
      samplingRate: samplingRate,
      frequencies: frequencies,
      samplesGenerated: samplesGenerated,
    ));
  }

  static Uint16List scaleUint16ListTo14Bit(Uint16List input) {
    final int maxInput = input.reduce((a, b) => a > b ? a : b); // Find the maximum value in the input list

    // Scale the values to the range [0, 16383]
    final scaledValues = input.map((value) => (value ~/ 4)).toList();
    final int maxScaledValues = scaledValues.reduce((a, b) => a > b ? a : b); // Find the maximum value in the input list
    final int minScaledValues = scaledValues.reduce((a, b) => a < b ? a : b); // Find the minimum value in the input list

    // Create a Uint16List from the scaled values
    final uint14List = Uint16List.fromList(scaledValues);

    return uint14List;
  }

  static Uint16List doubleListToUint16List(List<double> input) {
    final double maxInput = input.reduce((a, b) => a > b ? a : b); // Find the maximum value in the input list
    final double minInput = input.reduce((a, b) => a < b ? a : b); // Find the minimum value in the input list

    // Normalize the values to the range [minInput, maxInput]
    final List<double> zeroBasedValues = input.map((value) => (value - minInput)).toList();
    final double maxZeroBasedValues = zeroBasedValues.reduce((a, b) => a > b ? a : b); // Find the maximum value in the input list
    final double minZeroBasedValues = zeroBasedValues.reduce((a, b) => a < b ? a : b); // Find the minimum value in the input list

    final List<double> normalizedValues = zeroBasedValues.map((value) => (value / maxZeroBasedValues)).toList();
    final double maxNormalizedValues = normalizedValues.reduce((a, b) => a > b ? a : b); // Find the maximum value in the input list
    final double minNormalizedValues = normalizedValues.reduce((a, b) => a < b ? a : b); // Find the minimum value in the input list

    // Scale the normalized values to the range [0, 65535]
    final List<int> scaledValues = normalizedValues.map((value) => (value * 65535).round()).toList();
    final int maxScaledValues = scaledValues.reduce((a, b) => a > b ? a : b); // Find the maximum value in the input list
    final int minScaledValues = scaledValues.reduce((a, b) => a < b ? a : b); // Find the minimum value in the input list

    // Create a Uint16List from the scaled values
    final uint16List = Uint16List.fromList(scaledValues);

    return uint16List;
  }
}
