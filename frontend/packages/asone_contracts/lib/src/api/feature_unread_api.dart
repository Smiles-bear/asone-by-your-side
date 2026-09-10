import 'package:flutter/foundation.dart';

import '../models/feature_unread.dart';

/// Public contract for the unified unread state of feature entries.
abstract interface class FeatureUnreadApi {
  ValueListenable<FeatureUnreadSnapshot> get changes;

  Future<FeatureUnreadSnapshot> refresh();

  Future<void> markRead(FeatureUnreadKind kind, {DateTime? through});

  Future<int> messageBoardUnreadCount({String? assistantId});
}
