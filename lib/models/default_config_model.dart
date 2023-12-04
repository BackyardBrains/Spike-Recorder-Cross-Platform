import 'dart:convert';

class DefaultConfig {
  final Config? config;

  DefaultConfig({
    this.config,
  });

  DefaultConfig copyWith({
    Config? config,
  }) =>
      DefaultConfig(
        config: config ?? this.config,
      );

  factory DefaultConfig.fromRawJson(String str) =>
      DefaultConfig.fromJson(json.decode(str));

  String toRawJson() => json.encode(toJson());

  factory DefaultConfig.fromJson(Map<String, dynamic> json) => DefaultConfig(
        config: json["config"] == null ? null : Config.fromJson(json["config"]),
      );

  Map<String, dynamic> toJson() => {
        "config": config?.toJson(),
      };
}

class Config {
  final Version? version;
  final List<Board>? boards;

  Config({
    this.version,
    this.boards,
  });

  Config copyWith({
    Version? version,
    List<Board>? boards,
  }) =>
      Config(
        version: version ?? this.version,
        boards: boards ?? this.boards,
      );

  factory Config.fromRawJson(String str) => Config.fromJson(json.decode(str));

  String toRawJson() => json.encode(toJson());

  factory Config.fromJson(Map<String, dynamic> json) => Config(
        version: versionValues.map[json["version"]]!,
        boards: json["boards"] == null
            ? []
            : List<Board>.from(json["boards"]!.map((x) => Board.fromJson(x))),
      );

  Map<String, dynamic> toJson() => {
        "version": versionValues.reverse[version],
        "boards": boards == null
            ? []
            : List<dynamic>.from(boards!.map((x) => x.toJson())),
      };
}

class Board {
  final String? uniqueName;
  final String? userFriendlyFullName;
  final String? userFriendlyShortName;
  final String? hardwareComProtocolType;
  final BybProtocolType? bybProtocolType;
  final Version? bybProtocolVersion;
  final String? maxSampleRate;
  final String? maxNumberOfChannels;
  final int? sampleResolution;
  final String? supportedPlatforms;
  final String? productUrl;
  final String? helpUrl;
  final String? firmwareUpdateUrl;
  final String? iconUrl;
  final String? defaultTimeScale;
  final Version? defaultAmplitudeScale;
  final int? sampleRateIsFunctionOfNumberOfChannels;
  final MiniOsAppVersion? miniOsAppVersion;
  final MinAppVersion? minAndroidAppVersion;
  final MinAppVersion? minWinAppVersion;
  final MinAppVersion? minMacAppVersion;
  final MinAppVersion? minLinuxAppVersion;
  final int? p300CapabilityPresent;
  final Filter? filter;
  final List<Channel>? channels;
  final List<ExpansionBoard>? expansionBoards;
  final Usb? usb;

  Board({
    this.uniqueName,
    this.userFriendlyFullName,
    this.userFriendlyShortName,
    this.hardwareComProtocolType,
    this.bybProtocolType,
    this.bybProtocolVersion,
    this.maxSampleRate,
    this.maxNumberOfChannels,
    this.sampleResolution,
    this.supportedPlatforms,
    this.productUrl,
    this.helpUrl,
    this.firmwareUpdateUrl,
    this.iconUrl,
    this.defaultTimeScale,
    this.defaultAmplitudeScale,
    this.sampleRateIsFunctionOfNumberOfChannels,
    this.miniOsAppVersion,
    this.minAndroidAppVersion,
    this.minWinAppVersion,
    this.minMacAppVersion,
    this.minLinuxAppVersion,
    this.p300CapabilityPresent,
    this.filter,
    this.channels,
    this.expansionBoards,
    this.usb,
  });

  Board copyWith({
    String? uniqueName,
    String? userFriendlyFullName,
    String? userFriendlyShortName,
    String? hardwareComProtocolType,
    BybProtocolType? bybProtocolType,
    Version? bybProtocolVersion,
    String? maxSampleRate,
    String? maxNumberOfChannels,
    int? sampleResolution,
    String? supportedPlatforms,
    String? productUrl,
    String? helpUrl,
    String? firmwareUpdateUrl,
    String? iconUrl,
    String? defaultTimeScale,
    Version? defaultAmplitudeScale,
    int? sampleRateIsFunctionOfNumberOfChannels,
    MiniOsAppVersion? miniOsAppVersion,
    MinAppVersion? minAndroidAppVersion,
    MinAppVersion? minWinAppVersion,
    MinAppVersion? minMacAppVersion,
    MinAppVersion? minLinuxAppVersion,
    int? p300CapabilityPresent,
    Filter? filter,
    List<Channel>? channels,
    List<ExpansionBoard>? expansionBoards,
    Usb? usb,
  }) =>
      Board(
        uniqueName: uniqueName ?? this.uniqueName,
        userFriendlyFullName: userFriendlyFullName ?? this.userFriendlyFullName,
        userFriendlyShortName:
            userFriendlyShortName ?? this.userFriendlyShortName,
        hardwareComProtocolType:
            hardwareComProtocolType ?? this.hardwareComProtocolType,
        bybProtocolType: bybProtocolType ?? this.bybProtocolType,
        bybProtocolVersion: bybProtocolVersion ?? this.bybProtocolVersion,
        maxSampleRate: maxSampleRate ?? this.maxSampleRate,
        maxNumberOfChannels: maxNumberOfChannels ?? this.maxNumberOfChannels,
        sampleResolution: sampleResolution ?? this.sampleResolution,
        supportedPlatforms: supportedPlatforms ?? this.supportedPlatforms,
        productUrl: productUrl ?? this.productUrl,
        helpUrl: helpUrl ?? this.helpUrl,
        firmwareUpdateUrl: firmwareUpdateUrl ?? this.firmwareUpdateUrl,
        iconUrl: iconUrl ?? this.iconUrl,
        defaultTimeScale: defaultTimeScale ?? this.defaultTimeScale,
        defaultAmplitudeScale:
            defaultAmplitudeScale ?? this.defaultAmplitudeScale,
        sampleRateIsFunctionOfNumberOfChannels:
            sampleRateIsFunctionOfNumberOfChannels ??
                this.sampleRateIsFunctionOfNumberOfChannels,
        miniOsAppVersion: miniOsAppVersion ?? this.miniOsAppVersion,
        minAndroidAppVersion: minAndroidAppVersion ?? this.minAndroidAppVersion,
        minWinAppVersion: minWinAppVersion ?? this.minWinAppVersion,
        minMacAppVersion: minMacAppVersion ?? this.minMacAppVersion,
        minLinuxAppVersion: minLinuxAppVersion ?? this.minLinuxAppVersion,
        p300CapabilityPresent:
            p300CapabilityPresent ?? this.p300CapabilityPresent,
        filter: filter ?? this.filter,
        channels: channels ?? this.channels,
        expansionBoards: expansionBoards ?? this.expansionBoards,
        usb: usb ?? this.usb,
      );

  factory Board.fromRawJson(String str) => Board.fromJson(json.decode(str));

  String toRawJson() => json.encode(toJson());

  factory Board.fromJson(Map<String, dynamic> json) => Board(
        uniqueName: json["uniqueName"],
        userFriendlyFullName: json["userFriendlyFullName"],
        userFriendlyShortName: json["userFriendlyShortName"],
        hardwareComProtocolType: json["hardwareComProtocolType"],
        bybProtocolType: bybProtocolTypeValues.map[json["bybProtocolType"]]!,
        bybProtocolVersion: versionValues.map[json["bybProtocolVersion"]]!,
        maxSampleRate: json["maxSampleRate"],
        maxNumberOfChannels: json["maxNumberOfChannels"],
        sampleResolution: json["sampleResolution"],
        supportedPlatforms: json["supportedPlatforms"],
        productUrl: json["productURL"],
        helpUrl: json["helpURL"],
        firmwareUpdateUrl: json["firmwareUpdateUrl"],
        iconUrl: json["iconURL"],
        defaultTimeScale: json["defaultTimeScale"],
        defaultAmplitudeScale:
            versionValues.map[json["defaultAmplitudeScale"]]!,
        sampleRateIsFunctionOfNumberOfChannels:
            json["sampleRateIsFunctionOfNumberOfChannels"],
        miniOsAppVersion: miniOsAppVersionValues.map[json["miniOSAppVersion"]]!,
        minAndroidAppVersion:
            minAppVersionValues.map[json["minAndroidAppVersion"]]!,
        minWinAppVersion: minAppVersionValues.map[json["minWinAppVersion"]]!,
        minMacAppVersion: minAppVersionValues.map[json["minMacAppVersion"]]!,
        minLinuxAppVersion:
            minAppVersionValues.map[json["minLinuxAppVersion"]]!,
        p300CapabilityPresent: json["p300CapabilityPresent"],
        filter: json["filter"] == null ? null : Filter.fromJson(json["filter"]),
        channels: json["channels"] == null
            ? []
            : List<Channel>.from(
                json["channels"]!.map((x) => Channel.fromJson(x))),
        expansionBoards: json["expansionBoards"] == null
            ? []
            : List<ExpansionBoard>.from(json["expansionBoards"]!
                .map((x) => ExpansionBoard.fromJson(x))),
        usb: json["usb"] == null ? null : Usb.fromJson(json["usb"]),
      );

  Map<String, dynamic> toJson() => {
        "uniqueName": uniqueName,
        "userFriendlyFullName": userFriendlyFullName,
        "userFriendlyShortName": userFriendlyShortName,
        "hardwareComProtocolType": hardwareComProtocolType,
        "bybProtocolType": bybProtocolTypeValues.reverse[bybProtocolType],
        "bybProtocolVersion": versionValues.reverse[bybProtocolVersion],
        "maxSampleRate": maxSampleRate,
        "maxNumberOfChannels": maxNumberOfChannels,
        "sampleResolution": sampleResolution,
        "supportedPlatforms": supportedPlatforms,
        "productURL": productUrl,
        "helpURL": helpUrl,
        "firmwareUpdateUrl": firmwareUpdateUrl,
        "iconURL": iconUrl,
        "defaultTimeScale": defaultTimeScale,
        "defaultAmplitudeScale": versionValues.reverse[defaultAmplitudeScale],
        "sampleRateIsFunctionOfNumberOfChannels":
            sampleRateIsFunctionOfNumberOfChannels,
        "miniOSAppVersion": miniOsAppVersionValues.reverse[miniOsAppVersion],
        "minAndroidAppVersion":
            minAppVersionValues.reverse[minAndroidAppVersion],
        "minWinAppVersion": minAppVersionValues.reverse[minWinAppVersion],
        "minMacAppVersion": minAppVersionValues.reverse[minMacAppVersion],
        "minLinuxAppVersion": minAppVersionValues.reverse[minLinuxAppVersion],
        "p300CapabilityPresent": p300CapabilityPresent,
        "filter": filter?.toJson(),
        "channels": channels == null
            ? []
            : List<dynamic>.from(channels!.map((x) => x.toJson())),
        "expansionBoards": expansionBoards == null
            ? []
            : List<dynamic>.from(expansionBoards!.map((x) => x.toJson())),
        "usb": usb?.toJson(),
      };
}

enum BybProtocolType { BYB1, EMPTY }

final bybProtocolTypeValues =
    EnumValues({"BYB1": BybProtocolType.BYB1, "": BybProtocolType.EMPTY});

enum Version { EMPTY, THE_10 }

final versionValues = EnumValues({"": Version.EMPTY, "1.0": Version.THE_10});

class Channel {
  final String? userFriendlyFullName;
  final String? userFriendlyShortName;
  final int? activeByDefault;
  final int? filtered;
  final double? calibrationCoef;
  final int? channelIsCalibrated;
  final double? defaultVoltageScale;

  Channel({
    this.userFriendlyFullName,
    this.userFriendlyShortName,
    this.activeByDefault,
    this.filtered,
    this.calibrationCoef,
    this.channelIsCalibrated,
    this.defaultVoltageScale,
  });

  Channel copyWith({
    String? userFriendlyFullName,
    String? userFriendlyShortName,
    int? activeByDefault,
    int? filtered,
    double? calibrationCoef,
    int? channelIsCalibrated,
    double? defaultVoltageScale,
  }) =>
      Channel(
        userFriendlyFullName: userFriendlyFullName ?? this.userFriendlyFullName,
        userFriendlyShortName:
            userFriendlyShortName ?? this.userFriendlyShortName,
        activeByDefault: activeByDefault ?? this.activeByDefault,
        filtered: filtered ?? this.filtered,
        calibrationCoef: calibrationCoef ?? this.calibrationCoef,
        channelIsCalibrated: channelIsCalibrated ?? this.channelIsCalibrated,
        defaultVoltageScale: defaultVoltageScale ?? this.defaultVoltageScale,
      );

  factory Channel.fromRawJson(String str) => Channel.fromJson(json.decode(str));

  String toRawJson() => json.encode(toJson());

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
        userFriendlyFullName: json["userFriendlyFullName"],
        userFriendlyShortName: json["userFriendlyShortName"],
        activeByDefault: json["activeByDefault"],
        filtered: json["filtered"],
        calibrationCoef: json["calibrationCoef"],
        channelIsCalibrated: json["channelIsCalibrated"],
        defaultVoltageScale: json["defaultVoltageScale"]?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        "userFriendlyFullName": userFriendlyFullName,
        "userFriendlyShortName": userFriendlyShortName,
        "activeByDefault": activeByDefault,
        "filtered": filtered,
        "calibrationCoef": calibrationCoef,
        "channelIsCalibrated": channelIsCalibrated,
        "defaultVoltageScale": defaultVoltageScale,
      };
}

class ExpansionBoard {
  final String? boardType;
  final UserFriendlyFullName? userFriendlyFullName;
  final UserFriendlyShortName? userFriendlyShortName;
  final SupportedPlatforms? supportedPlatforms;
  final String? maxNumberOfChannels;
  final String? maxSampleRate;
  final String? productUrl;
  final String? helpUrl;
  final String? iconUrl;
  final String? defaultTimeScale;
  final Version? defaultAmplitudeScale;
  final List<Channel>? channels;

  ExpansionBoard({
    this.boardType,
    this.userFriendlyFullName,
    this.userFriendlyShortName,
    this.supportedPlatforms,
    this.maxNumberOfChannels,
    this.maxSampleRate,
    this.productUrl,
    this.helpUrl,
    this.iconUrl,
    this.defaultTimeScale,
    this.defaultAmplitudeScale,
    this.channels,
  });

  ExpansionBoard copyWith({
    String? boardType,
    UserFriendlyFullName? userFriendlyFullName,
    UserFriendlyShortName? userFriendlyShortName,
    SupportedPlatforms? supportedPlatforms,
    String? maxNumberOfChannels,
    String? maxSampleRate,
    String? productUrl,
    String? helpUrl,
    String? iconUrl,
    String? defaultTimeScale,
    Version? defaultAmplitudeScale,
    List<Channel>? channels,
  }) =>
      ExpansionBoard(
        boardType: boardType ?? this.boardType,
        userFriendlyFullName: userFriendlyFullName ?? this.userFriendlyFullName,
        userFriendlyShortName:
            userFriendlyShortName ?? this.userFriendlyShortName,
        supportedPlatforms: supportedPlatforms ?? this.supportedPlatforms,
        maxNumberOfChannels: maxNumberOfChannels ?? this.maxNumberOfChannels,
        maxSampleRate: maxSampleRate ?? this.maxSampleRate,
        productUrl: productUrl ?? this.productUrl,
        helpUrl: helpUrl ?? this.helpUrl,
        iconUrl: iconUrl ?? this.iconUrl,
        defaultTimeScale: defaultTimeScale ?? this.defaultTimeScale,
        defaultAmplitudeScale:
            defaultAmplitudeScale ?? this.defaultAmplitudeScale,
        channels: channels ?? this.channels,
      );

  factory ExpansionBoard.fromRawJson(String str) =>
      ExpansionBoard.fromJson(json.decode(str));

  String toRawJson() => json.encode(toJson());

  factory ExpansionBoard.fromJson(Map<String, dynamic> json) => ExpansionBoard(
        boardType: json["boardType"],
        userFriendlyFullName:
            userFriendlyFullNameValues.map[json["userFriendlyFullName"]]!,
        userFriendlyShortName:
            userFriendlyShortNameValues.map[json["userFriendlyShortName"]]!,
        supportedPlatforms:
            supportedPlatformsValues.map[json["supportedPlatforms"]],
        maxNumberOfChannels: json["maxNumberOfChannels"],
        maxSampleRate: json["maxSampleRate"],
        productUrl: json["productURL"],
        helpUrl: json["helpURL"],
        iconUrl: json["iconURL"],
        defaultTimeScale: json["defaultTimeScale"],
        defaultAmplitudeScale:
            versionValues.map[json["defaultAmplitudeScale"]] ?? Version.EMPTY,
        channels: json["channels"] == null
            ? []
            : List<Channel>.from(
                json["channels"]!.map((x) => Channel.fromJson(x))),
      );

  Map<String, dynamic> toJson() => {
        "boardType": boardType,
        "userFriendlyFullName":
            userFriendlyFullNameValues.reverse[userFriendlyFullName],
        "userFriendlyShortName":
            userFriendlyShortNameValues.reverse[userFriendlyShortName],
        "supportedPlatforms":
            supportedPlatformsValues.reverse[supportedPlatforms],
        "maxNumberOfChannels": maxNumberOfChannels,
        "maxSampleRate": maxSampleRate,
        "productURL": productUrl,
        "helpURL": helpUrl,
        "iconURL": iconUrl,
        "defaultTimeScale": defaultTimeScale,
        "defaultAmplitudeScale": versionValues.reverse[defaultAmplitudeScale],
        "channels": channels == null
            ? []
            : List<dynamic>.from(channels!.map((x) => x.toJson())),
      };
}

enum SupportedPlatforms { ANDROID_IOS_WIN_MAC_LINUX, IOS, WIN }

final supportedPlatformsValues = EnumValues({
  "android,ios,win,mac,linux": SupportedPlatforms.ANDROID_IOS_WIN_MAC_LINUX,
  "ios": SupportedPlatforms.IOS,
  "win": SupportedPlatforms.WIN
});

enum UserFriendlyFullName {
  ADDITIONAL_ANALOG_INPUT_CHANNELS,
  DEFAULT_EVENTS_DETECTION_EXPANSION_BOARD,
  THE_JOYSTICK_CONTROL,
  THE_REFLEX_HAMMER
}

final userFriendlyFullNameValues = EnumValues({
  "Additional analog input channels":
      UserFriendlyFullName.ADDITIONAL_ANALOG_INPUT_CHANNELS,
  "Default - events detection expansion board":
      UserFriendlyFullName.DEFAULT_EVENTS_DETECTION_EXPANSION_BOARD,
  "The Joystick control": UserFriendlyFullName.THE_JOYSTICK_CONTROL,
  "The Reflex Hammer": UserFriendlyFullName.THE_REFLEX_HAMMER
});

enum UserFriendlyShortName { ANALOG_X_2, EVENTS_DETECTION, HAMMER, JOYSTICK }

final userFriendlyShortNameValues = EnumValues({
  "Analog x 2": UserFriendlyShortName.ANALOG_X_2,
  "Events detection": UserFriendlyShortName.EVENTS_DETECTION,
  "Hammer": UserFriendlyShortName.HAMMER,
  "Joystick": UserFriendlyShortName.JOYSTICK
});

class Filter {
  final String? signalType;
  final int? lowPassOn;
  final String? lowPassCutoff;
  final int? highPassOn;
  final String? highPassCutoff;
  final NotchFilterState? notchFilterState;

  Filter({
    this.signalType,
    this.lowPassOn,
    this.lowPassCutoff,
    this.highPassOn,
    this.highPassCutoff,
    this.notchFilterState,
  });

  Filter copyWith({
    String? signalType,
    int? lowPassOn,
    String? lowPassCutoff,
    int? highPassOn,
    String? highPassCutoff,
    NotchFilterState? notchFilterState,
  }) =>
      Filter(
        signalType: signalType ?? this.signalType,
        lowPassOn: lowPassOn ?? this.lowPassOn,
        lowPassCutoff: lowPassCutoff ?? this.lowPassCutoff,
        highPassOn: highPassOn ?? this.highPassOn,
        highPassCutoff: highPassCutoff ?? this.highPassCutoff,
        notchFilterState: notchFilterState ?? this.notchFilterState,
      );

  factory Filter.fromRawJson(String str) => Filter.fromJson(json.decode(str));

  String toRawJson() => json.encode(toJson());

  factory Filter.fromJson(Map<String, dynamic> json) => Filter(
        signalType: json["signalType"],
        lowPassOn: json["lowPassON"],
        lowPassCutoff: json["lowPassCutoff"],
        highPassOn: json["highPassON"],
        highPassCutoff: json["highPassCutoff"],
        notchFilterState: notchFilterStateValues.map[json["notchFilterState"]]!,
      );

  Map<String, dynamic> toJson() => {
        "signalType": signalType,
        "lowPassON": lowPassOn,
        "lowPassCutoff": lowPassCutoff,
        "highPassON": highPassOn,
        "highPassCutoff": highPassCutoff,
        "notchFilterState": notchFilterStateValues.reverse[notchFilterState],
      };
}

enum NotchFilterState { NOTCH60_HZ, NOTCH_OFF }

final notchFilterStateValues = EnumValues({
  "notch60Hz": NotchFilterState.NOTCH60_HZ,
  "notchOff": NotchFilterState.NOTCH_OFF
});

enum MinAppVersion { THE_100 }

final minAppVersionValues = EnumValues({"1.0.0": MinAppVersion.THE_100});

enum MiniOsAppVersion { THE_300 }

final miniOsAppVersionValues = EnumValues({"3.0.0": MiniOsAppVersion.THE_300});

class Usb {
  final String? vid;
  final String? pid;

  Usb({
    this.vid,
    this.pid,
  });

  Usb copyWith({
    String? vid,
    String? pid,
  }) =>
      Usb(
        vid: vid ?? this.vid,
        pid: pid ?? this.pid,
      );

  factory Usb.fromRawJson(String str) => Usb.fromJson(json.decode(str));

  String toRawJson() => json.encode(toJson());

  factory Usb.fromJson(Map<String, dynamic> json) => Usb(
        vid: json["VID"],
        pid: json["PID"],
      );

  Map<String, dynamic> toJson() => {
        "VID": vid,
        "PID": pid,
      };
}

class EnumValues<T> {
  Map<String, T> map;
  late Map<T, String> reverseMap;

  EnumValues(this.map);

  Map<T, String> get reverse {
    reverseMap = map.map((k, v) => MapEntry(v, k));
    return reverseMap;
  }
}
