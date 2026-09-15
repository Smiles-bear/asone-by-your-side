import 'dart:async';

/// 资料保存成功后的失效通知；不携带头像或其他个人资料。
abstract final class AssistantProfileEvents {
  static final _events = StreamController<String>.broadcast();
  static Stream<String> get stream => _events.stream;
  static void notify(String assistantId) => _events.add(assistantId);
}
