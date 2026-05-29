import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

class DeviceService {
  static Future<String> getDeviceId() async {
    final info = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final android = await info.androidInfo;
      // androidId — стабилен, не сбрасывается при переустановке
      // сбрасывается только при factory reset — это приемлемо
      return android.id;
    } else if (Platform.isIOS) {
      final ios = await info.iosInfo;
      // identifierForVendor — сбрасывается при полном удалении приложения
      return ios.identifierForVendor ?? 'unknown';
    }

    return 'unknown';
  }
}
