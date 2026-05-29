import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

class DeviceInfoHelper {
  static Future<String> getDeviceId() async {
    final plugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final info = await plugin.androidInfo;
      return info.id;
    }
    if (Platform.isIOS) {
      final info = await plugin.iosInfo;
      return info.identifierForVendor ?? 'unknown';
    }
    return 'unknown';
  }
}
