import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config_secret_storage.dart';
import 'model_secret_store.dart';

/// API Key 存安全存储，其余用户配置存本地 SharedPreferences。
class AppConfig {
  final String apiKey;
  final String baseUrl;
  final String model;
  final bool darkMode;
  final String? defaultModelServiceId;
  final bool showChatAvatars;
  final String themeColorKey;
  final String chatBackgroundKey;
  final String chatBackgroundPath;

  const AppConfig({
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    this.darkMode = false,
    this.defaultModelServiceId,
    this.showChatAvatars = true,
    this.themeColorKey = 'coral',
    this.chatBackgroundKey = 'default',
    this.chatBackgroundPath = '',
  });

  bool get isValid =>
      apiKey.trim().isNotEmpty &&
      baseUrl.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  AppConfig copyWith({
    String? apiKey,
    String? baseUrl,
    String? model,
    bool? darkMode,
    String? defaultModelServiceId,
    bool? showChatAvatars,
    String? themeColorKey,
    String? chatBackgroundKey,
    String? chatBackgroundPath,
  }) => AppConfig(
    apiKey: apiKey ?? this.apiKey,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    darkMode: darkMode ?? this.darkMode,
    defaultModelServiceId: defaultModelServiceId ?? this.defaultModelServiceId,
    showChatAvatars: showChatAvatars ?? this.showChatAvatars,
    themeColorKey: themeColorKey ?? this.themeColorKey,
    chatBackgroundKey: chatBackgroundKey ?? this.chatBackgroundKey,
    chatBackgroundPath: chatBackgroundPath ?? this.chatBackgroundPath,
  );

  static const _kBaseUrl = 'base_url';
  static const _kModel = 'model';
  static const _kDarkMode = 'dark_mode';
  static const _kDefaultModelServiceId = 'default_model_service_id';
  static const _kShowChatAvatars = 'show_chat_avatars';
  static const _kThemeColorKey = 'theme_color_key';
  static const _kChatBackgroundKey = 'chat_background_key';
  static const _kChatBackgroundPath = 'chat_background_path';

  static Future<AppConfig> load({ModelSecretStore? secretStore}) async {
    final p = await SharedPreferences.getInstance();
    return AppConfig(
      apiKey: await AppConfigSecretStorage(store: secretStore).load(p),
      baseUrl: p.getString(_kBaseUrl) ?? '',
      model: p.getString(_kModel) ?? '',
      darkMode: p.getBool(_kDarkMode) ?? false,
      defaultModelServiceId: p.getString(_kDefaultModelServiceId),
      showChatAvatars: p.getBool(_kShowChatAvatars) ?? true,
      themeColorKey: p.getString(_kThemeColorKey) ?? 'coral',
      chatBackgroundKey: _normalizedChatBackgroundKey(
        p.getString(_kChatBackgroundKey),
      ),
      chatBackgroundPath: p.getString(_kChatBackgroundPath) ?? '',
    );
  }

  Future<void> save({ModelSecretStore? secretStore}) async {
    final p = await SharedPreferences.getInstance();
    await AppConfigSecretStorage(store: secretStore).save(p, apiKey);
    await p.setString(_kBaseUrl, baseUrl);
    await p.setString(_kModel, model);
    await p.setBool(_kDarkMode, darkMode);
    await p.setBool(_kShowChatAvatars, showChatAvatars);
    await p.setString(_kThemeColorKey, themeColorKey);
    await p.setString(_kChatBackgroundKey, chatBackgroundKey);
    await p.setString(_kChatBackgroundPath, chatBackgroundPath);
    if (defaultModelServiceId != null) {
      await p.setString(_kDefaultModelServiceId, defaultModelServiceId!);
    } else {
      await p.remove(_kDefaultModelServiceId);
    }
  }

  static String _normalizedChatBackgroundKey(String? value) =>
      value == 'custom' ? 'custom' : 'default';

  /// 电脑后端只允许作为显式开发 adapter；release 产物即使误传 define 也会强制本地核心。
  static const bool _remoteDevelopmentCoreRequested = bool.fromEnvironment(
    'AZRUIYOI_DEV_REMOTE_CORE',
    defaultValue: false,
  );
  static const bool useRemoteDevelopmentCore =
      _remoteDevelopmentCoreRequested && !kReleaseMode;

  /// 本地开发验收包可显式跳过账号云准入；Release 即使误传 define 也不会生效。
  static const bool _developerAccessBypassRequested = bool.fromEnvironment(
    'AZRUIYOI_DEV_BYPASS_ACCESS',
    defaultValue: false,
  );
  static const bool developerAccessBypass =
      _developerAccessBypassRequested && !kReleaseMode;

  static const String coreModeLabel = useRemoteDevelopmentCore
      ? 'DEV · 远端核心'
      : '手机本地核心';

  static const String developerAccessLabel = 'DEV · 无邀请码验收';

  static const String developmentModeLabel = developerAccessBypass
      ? developerAccessLabel
      : coreModeLabel;
  static const bool developmentModeEnabled =
      developerAccessBypass || useRemoteDevelopmentCore;

  static String defaultBackendUrl() => const String.fromEnvironment(
    'AZRUIYOI_DEV_BACKEND_URL',
    defaultValue: '',
  );

  static String get backendUrl => defaultBackendUrl();

  /// 账号云地址只包含身份、权益和版本接口，不是聊天后端。
  static const String accountBackendUrl = String.fromEnvironment(
    'AZRUIYOI_ACCOUNT_BASE_URL',
    defaultValue: '',
  );

  /// 必须在发布构建时嵌入，不从运行时网络接口信任替换值。
  static const String runtimeLeaseSigningKeyId = String.fromEnvironment(
    'AZRUIYOI_LEASE_SIGNING_KEY_ID',
    defaultValue: '',
  );
  static const String runtimeLeasePublicKey = String.fromEnvironment(
    'AZRUIYOI_LEASE_PUBLIC_KEY',
    defaultValue: '',
  );
  static const String releaseChannel = String.fromEnvironment(
    'AZRUIYOI_RELEASE_CHANNEL',
    defaultValue: 'official',
  );
}
