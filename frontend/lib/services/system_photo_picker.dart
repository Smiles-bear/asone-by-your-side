import 'package:flutter/services.dart';

class SystemPhotoPicker {
  const SystemPhotoPicker._();

  static const _channel = MethodChannel('com.ruyi.azruiyoi/photo_picker');

  static Future<String?> pickImage() =>
      _channel.invokeMethod<String>('pickImage');

  static Future<String?> takePhoto() =>
      _channel.invokeMethod<String>('takePhoto');
}
