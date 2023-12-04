import 'filter_select_enum.dart';

class FilterSetup {
  const FilterSetup({
    this.isFilterOn = true,
    required this.filterType,
    required this.filterConfiguration,
    required this.channelCount,
  });

  final bool isFilterOn;
  final FilterType filterType;
  final int channelCount;
  final FilterConfiguration filterConfiguration;

  Map<String, dynamic> toJson() {
    return {
      'isFilterOn': isFilterOn,
      'filterType': filterType.toString(), // Assuming FilterType is an enum
      'channelCount': channelCount,
      'filterConfiguration': filterConfiguration.toJson(),
    };
  }

  FilterSetup copyWith({
    bool? isFilterOn,
    FilterType? filterType,
    int? channelCount,
    FilterConfiguration? filterConfiguration,
  }) {
    return FilterSetup(
      isFilterOn: isFilterOn ?? this.isFilterOn,
      filterType: filterType ?? this.filterType,
      channelCount: channelCount ?? this.channelCount,
      filterConfiguration: filterConfiguration ?? this.filterConfiguration,
    );
  }
}

class FilterConfiguration {
  const FilterConfiguration({
    required this.cutOffFrequency,
    required this.sampleRate,
  });

  final int cutOffFrequency;
  final int sampleRate;

  Map<String, dynamic> toJson() {
    return {
      'cutOffFrequency': cutOffFrequency,
      'sampleRate': sampleRate,
    };
  }
}
