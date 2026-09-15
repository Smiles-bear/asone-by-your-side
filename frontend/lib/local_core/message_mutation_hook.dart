import 'core_database.dart';

/// 消息写入后的可选扩展钩子。
///
/// 社区版不挂载时保持 no-op；私有宿主可挂载记忆整理队列等后处理。
abstract interface class MessageMutationHook {
  Future<void> registerMessage(String messageId, {DateTime? changedAt});

  Future<void> markChanged(String messageId, {DateTime? changedAt});

  Future<void> markDeleted(String messageId, {DateTime? changedAt});
}

final class NoopMessageMutationHook implements MessageMutationHook {
  const NoopMessageMutationHook();

  @override
  Future<void> registerMessage(String messageId, {DateTime? changedAt}) async {}

  @override
  Future<void> markChanged(String messageId, {DateTime? changedAt}) async {}

  @override
  Future<void> markDeleted(String messageId, {DateTime? changedAt}) async {}
}

/// 私有宿主可在创建仓储前挂载消息后处理；公开版保持 null。
abstract final class MessageMutationHooksBinding {
  static MessageMutationHook Function(CoreDatabase database)? create;

  static MessageMutationHook resolve(CoreDatabase database) =>
      create?.call(database) ?? const NoopMessageMutationHook();
}
