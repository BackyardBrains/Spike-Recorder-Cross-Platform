import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Web registrar for Flutter's plugin system.
///
/// The recording API itself is exposed via conditional exports in
/// `nwbfile_plugin.dart` and calls into the Emscripten `NWBPlugin` module
/// loaded from `web/nwb/nwbfile_plugin.js`.
class NwbfilePluginWeb {
  static void registerWith(Registrar registrar) {}
}
