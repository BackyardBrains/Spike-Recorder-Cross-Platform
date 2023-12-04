import 'dart:io';

import 'package:spikerbox_architecture/models/serial_util/serial_util_android.dart';
import 'package:spikerbox_architecture/models/serial_util/serial_util_window.dart';
import 'serial_util_check.dart';

SerialUtil getSerialUtil() {
  if(Platform.isWindows || Platform.isMacOS) {
    return SerialUtilWindow();
  } else if (Platform.isAndroid) {
    return SerialUtilAndroid();
  }
  return SerialUtilAndroid();
}
