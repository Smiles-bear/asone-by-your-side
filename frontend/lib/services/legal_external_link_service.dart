import 'package:flutter/services.dart';

class LegalExternalLinkService {
  const LegalExternalLinkService._();

  static const _channel = MethodChannel('com.ruyi.azruiyoi/legal_links');

  static Future<bool> open(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
