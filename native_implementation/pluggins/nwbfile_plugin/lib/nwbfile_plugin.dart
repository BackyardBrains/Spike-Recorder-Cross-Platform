/// Cross-platform NWB recording API (native FFI or web WASM).
library nwbfile_plugin;

export 'nwbfile_plugin_io.dart'
    if (dart.library.html) 'nwbfile_plugin_html.dart';
