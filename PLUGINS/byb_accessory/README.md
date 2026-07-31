# byb_accessory

Flutter iOS plugin wrapper for Backyard Brains `ExternalAccessory` session handling.

## iOS setup

In your host app `Info.plist`, add the accessory protocol(s) under
`UISupportedExternalAccessoryProtocols`.

Example:

```xml
<key>UISupportedExternalAccessoryProtocols</key>
<array>
  <string>com.backyardbrains.protocol</string>
</array>
```

Use the exact protocol string supported by your accessory firmware.

## BBAudioManager

`Classes/BBAudioManager.{h,m}` is a **minimal stub** so `BybAccessoryPlugin` can call `addMfiDeviceWithModelNumber:andSerial:` / `removeMfiDevice…` without linking the entire Spike Recorder iOS app.

A **reference copy** of upstream `source/src/Audio` and `source/src/accessory` from Spike Recorder iOS lives under `ios/vendor/Spike-Recorder-IOS-reference/`. Those files are excluded from the CocoaPods build; see `ios/vendor/README.md` for why and how to move toward the real implementation.

## Dart API

```dart
import 'package:byb_accessory/byb_accessory.dart';

await BybAccessory.initWithProtocol('com.backyardbrains.protocol');
final accessories = await BybAccessory.getConnectedAccessories();
final connected = await BybAccessory.connect(
  name: accessories.isNotEmpty ? accessories.first : null,
);

if (connected) {
  final info = await BybAccessory.getAccessoryInfo();
  print(info);
}
```

Available methods:

- `initWithProtocol(String protocol)`
- `setProtocol(String protocol)`
- `getConnectedAccessories()`
- `connect({String? name})`
- `disconnect()`
- `isConnected()`
- `getAccessoryInfo()`

