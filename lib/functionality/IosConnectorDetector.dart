import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

enum ConnectorType { lightning, usbC, unknown }

class IosConnectorDetector {
  static Future<ConnectorType> getConnectorType() async {
    if (!Platform.isIOS) return ConnectorType.unknown;

    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
    
    // The 'utsname.machine' provides the identifier like "iPhone16,1"
    String machine = iosInfo.utsname.machine;

    // 1. Check iPhones: USB-C started with the iPhone 15 series (iPhone15,4+)
    if (machine.startsWith('iPhone')) {
      final versionMatch = RegExp(r'iPhone(\d+),').firstMatch(machine);
      if (versionMatch != null) {
        int majorVersion = int.parse(versionMatch.group(1)!);
        // iPhone 15 series and newer use USB-C
        // Note: iPhone15,4 is iPhone 15, iPhone16,x is iPhone 16
        return (majorVersion >= 15 && machine != 'iPhone15,2' && machine != 'iPhone15,3') 
            ? ConnectorType.usbC 
            : ConnectorType.lightning;
      }
    }

    // 2. Check iPads: Transition is more fragmented
    if (machine.startsWith('iPad')) {
      // USB-C iPads include:
      // iPad Pro 11" (All), iPad Pro 12.9" (3rd gen+), iPad Air (4th gen+), iPad mini (6th gen+), iPad (10th gen+)
      List<String> usbCIpads = [
        'iPad8,1', 'iPad8,2', 'iPad8,3', 'iPad8,4', // Pro 11 1st
        'iPad8,5', 'iPad8,6', 'iPad8,7', 'iPad8,8', // Pro 12.9 3rd
        'iPad8,9', 'iPad8,10', 'iPad8,11', 'iPad8,12', // Pro 11 2nd / 12.9 4th
        'iPad13,1', 'iPad13,2', // Air 4th
        'iPad13,4', 'iPad13,5', 'iPad13,6', 'iPad13,7', 'iPad13,8', 'iPad13,9', 'iPad13,10', 'iPad13,11', // Pro M1
        'iPad14,1', 'iPad14,2', // mini 6th
        'iPad13,18', 'iPad13,19', // iPad 10th
      ];
      
      if (usbCIpads.any((id) => machine.startsWith(id))) return ConnectorType.usbC;
      return ConnectorType.lightning;
    }

    return ConnectorType.unknown;
  }
}