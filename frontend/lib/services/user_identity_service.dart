import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'avatar_storage_service.dart';

@immutable
class UserIdentity {
  const UserIdentity({
    required this.nickname,
    required this.accountNumber,
    required this.avatarPath,
  });

  final String nickname;
  final String accountNumber;
  final String avatarPath;
}

class UserIdentityService {
  UserIdentityService._();

  @visibleForTesting
  UserIdentityService.testing();

  static final UserIdentityService instance = UserIdentityService._();

  static const _nicknameKey = 'user_identity_nickname';
  static const _accountNumberKey = 'user_identity_account_number';
  static const _avatarPathKey = 'user_identity_avatar_path';

  final ValueNotifier<UserIdentity> notifier = ValueNotifier(
    const UserIdentity(nickname: 'User', accountNumber: '', avatarPath: ''),
  );

  UserIdentity get value => notifier.value;

  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    var accountNumber = preferences.getString(_accountNumberKey) ?? '';
    if (!RegExp(r'^\d{10}$').hasMatch(accountNumber)) {
      accountNumber = _generateAccountNumber();
      await preferences.setString(_accountNumberKey, accountNumber);
    }

    final storedNickname = preferences.getString(_nicknameKey)?.trim() ?? '';
    final avatarPath = preferences.getString(_avatarPathKey) ?? '';
    notifier.value = UserIdentity(
      nickname: storedNickname.isEmpty ? 'User' : storedNickname,
      accountNumber: accountNumber,
      avatarPath: avatarPath,
    );
  }

  Future<void> update({
    required String nickname,
    String? selectedAvatarPath,
    bool restoreDefaultAvatar = false,
  }) async {
    final normalizedNickname = nickname.trim().isEmpty
        ? 'User'
        : nickname.trim();
    var avatarPath = value.avatarPath;

    if (selectedAvatarPath != null && selectedAvatarPath.isNotEmpty) {
      avatarPath = await AvatarStorageService.importImage(
        selectedAvatarPath,
        category: 'user',
      );
    } else if (restoreDefaultAvatar) {
      avatarPath = '';
    }

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_nicknameKey, normalizedNickname);
    await preferences.setString(_avatarPathKey, avatarPath);
    notifier.value = UserIdentity(
      nickname: normalizedNickname,
      accountNumber: value.accountNumber,
      avatarPath: avatarPath,
    );
  }

  String _generateAccountNumber() {
    final random = Random.secure();
    final buffer = StringBuffer(random.nextInt(9) + 1);
    for (var index = 1; index < 10; index++) {
      buffer.write(random.nextInt(10));
    }
    return buffer.toString();
  }
}
