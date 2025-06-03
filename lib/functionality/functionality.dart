import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../models/default_config_model.dart';
import 'package:http/http.dart' as https;

class SetUpFunctionality {
  static DefaultConfig? defaultDeviceConfig;
  Future<Board?> setTheDeviceSetting(String? deviceName) async {
    if (deviceName != null) {
      DefaultConfig data = await SetUpFunctionality().jsonLoad();
      deviceName = deviceName.split(";").first;
      Iterable<Board>? deviceConfiguration =
          data.config!.boards?.where((e) => e.uniqueName == deviceName);

      print("setTheDeviceSetting: ${deviceConfiguration?.first.uniqueName}");
      return deviceConfiguration?.first;
    }
    return null;
  }
  static Future<dynamic> getDeviceCatalog(localData) async {
    String url =
        "https://firebasestorage.googleapis.com/v0/b/webspikerecorder.appspot.com/o/default_config.json?alt=media&token=8b0f5e9c-110a-455d-99e9-9fbc0a875f99";
    print("getDeviceCatalog");
    var config = localData;
    try {
      final response = (await https.get(Uri.parse(url)));
      if (response.statusCode == 200) {
        print("found https");
        config = response.body;
      } else {
        print("error https");
        config = localData;
      }
    } catch (err) {
      config = localData;
      print("err");
      print(err);
    }

    return config;
  }


  Future<Config> getAllDeviceList() async {
    print("getAllDeviceList000");
    print(defaultDeviceConfig);
    if (defaultDeviceConfig != null) {
      print("defaultDeviceConfig");
      DefaultConfig data = await SetUpFunctionality().jsonLoad();
      defaultDeviceConfig = data;
      return defaultDeviceConfig!.config!;
    } else {
      print("load assets");
      String jsonString = await rootBundle.loadString('assets/default_config.json');
      jsonString = await getDeviceCatalog(jsonString);
      if ( jsonString.trim() != "") {
        DefaultConfig data = DefaultConfig.fromRawJson(jsonString);
        defaultDeviceConfig = data;
        return defaultDeviceConfig!.config!;
      } else {
        DefaultConfig data = await SetUpFunctionality().jsonLoad();
        defaultDeviceConfig = data;
        return defaultDeviceConfig!.config!;
      }
    }
  }

  Future<DefaultConfig> jsonLoad() async {
    String jsonString =
        await rootBundle.loadString('assets/default_config.json');
    DefaultConfig data = DefaultConfig.fromRawJson(jsonString);
    return data;
  }
}
