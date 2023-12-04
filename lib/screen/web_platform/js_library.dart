export 'package:spikerbox_architecture/screen/web_platform/js_listener_native.dart'
    if (dart.library.html) 'package:spikerbox_architecture/screen/web_platform/js_listener_web.dart'
    if (Platform.isWindows) 'package:spikerbox_architecture/screen/web_platform/js_listener_web.dart';
