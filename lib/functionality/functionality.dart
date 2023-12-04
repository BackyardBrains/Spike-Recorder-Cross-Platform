import 'package:flutter/services.dart';

import '../models/default_config_model.dart';

class SetUpFunctionality {
  Future<Board?> setTheDeviceSetting(String? deviceName) async {
    if (deviceName != null) {
      DefaultConfig data = await SetUpFunctionality().jsonLoad();
      deviceName = deviceName.split(";").first;
      Iterable<Board>? deviceConfiguration =
          data.config!.boards?.where((e) => e.uniqueName == deviceName);

      return deviceConfiguration?.first;
    }
    return null;
  }

  Future<Config> getAllDeviceList() async {
    DefaultConfig data = await SetUpFunctionality().jsonLoad();
    return data.config!;
  }

  Future<DefaultConfig> jsonLoad() async {
    String jsonString =
        await rootBundle.loadString('assets/default_config.json');
    DefaultConfig data = DefaultConfig.fromRawJson(jsonString);
    return data;
  }
}
