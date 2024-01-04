import 'enveloping_config.dart';

int skipCount = 0;

final List<EnvelopingConfig> envelopingConfig = List.generate(
  6,
  (index) => EnvelopingConfig(),
);

int samplesToFetch = 0;
