import 'package:squadron/squadron.dart';

import 'identify_service.dart';
import 'sample_service.dart';

void start(List command) => run((startRequest) {
      final channel = Channel.deserialize(startRequest.args[0])!;
      final identityClient = IdentityClient(channel);
      return SampleServiceImpl(identityClient);
    }, command);