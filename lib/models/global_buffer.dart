import 'package:spikerbox_architecture/models/models.dart';

late final BufferHandler preEscapeSequenceBuffer;

FrameDetect frameDetect = FrameDetect(channelCount: 1);
final SerialUtil serialUtil = SerialUtil();
bool isDataIdentified = false;
LocalPlugin localPlugin = LocalPlugin();
