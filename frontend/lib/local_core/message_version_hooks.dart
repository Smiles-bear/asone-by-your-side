import 'core_database.dart';

/// 消息版本生命周期钩子（记忆/关系状态域的派生数据通知）。
///
/// 宿主私有版在启动时通过 [MessageVersionLifecycleHooksBinding] 挂载
/// 钩子工厂；公开版不挂载，消息版本管理、分支切换与软删除独立运行，
/// 版本服务文件因此保持零私有域 import。
abstract interface class MessageVersionLifecycleHooks {
  /// 登记新消息（可携带变更时间）。
  Future<void> registerMessage(String messageId, {DateTime? changedAt});

  /// 消息内容变化，标记派生数据需重算。
  Future<void> markMessageChanged(String messageId);

  /// 消息删除通知。
  Future<void> markMessageDeleted(String messageId);
}

/// 进程级绑定点：私有宿主挂载钩子工厂（以版本服务自身的数据库创建，
/// 与历史默认构造行为一致）；公开壳保持 null。
final class MessageVersionLifecycleHooksBinding {
  MessageVersionLifecycleHooksBinding._();

  static MessageVersionLifecycleHooks Function(CoreDatabase? coreDatabase)?
  create;
}
