class FilterSettings {
  final int? sampleRate;
  final int? cutOff;

  const FilterSettings({
    this.sampleRate,
    this.cutOff,
  });

  factory FilterSettings.fromJson(Map<String, dynamic> json) => FilterSettings(
        sampleRate: json["SampleRate"],
        cutOff: json["cutOff"],
      );

  Map<String, dynamic> toJson() => {
        "SampleRate": sampleRate,
        "cutOff": cutOff,
      };
}
