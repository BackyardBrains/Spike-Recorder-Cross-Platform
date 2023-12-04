class NotchSetFrequencySetting {
  NotchSetFrequencyEnum setFrequency;
  bool isNotchFrequency;

  NotchSetFrequencySetting(
      {required this.isNotchFrequency, required this.setFrequency});
}

enum NotchSetFrequencyEnum { fiftyHertz, sixtyHertz }
