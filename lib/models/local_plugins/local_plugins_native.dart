import 'dart:io';
import 'package:spikerbox_architecture/models/local_plugins/local_plugins_check.dart';
import 'local_plugins_window.dart';
import 'local_plugins_android.dart';

LocalPlugin getLocalPlugins() {
  if (Platform.isWindows) {
    return LocalPluginWindow();
  } else if (Platform.isAndroid) {
    return LocalPluginAndroid();
  }
  return LocalPluginAndroid();
}
