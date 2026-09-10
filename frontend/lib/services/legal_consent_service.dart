import 'package:shared_preferences/shared_preferences.dart';

class LegalConsentService {
  const LegalConsentService._();

  static const currentVersion = '1.1-20260906';
  static const _acceptedVersionKey = 'legal.accepted_version';
  static const _acceptedAtKey = 'legal.accepted_at';

  static Future<bool> hasAcceptedCurrentVersion() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_acceptedVersionKey) == currentVersion;
  }

  static Future<void> acceptCurrentVersion() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_acceptedVersionKey, currentVersion);
    await preferences.setString(
      _acceptedAtKey,
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  static Future<void> withdraw() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_acceptedVersionKey);
    await preferences.remove(_acceptedAtKey);
  }
}
