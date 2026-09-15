import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 任务保护管理器
///
/// 负责根据运行中的任务数量，自动启动/停止 Android Foreground Service。
///
/// 生命周期：
/// - 第一个需要后台保护的任务开始运行时，启动 Foreground Service
/// - 多个任务同时运行时，只保持一个 Service，不重复启动
/// - 最后一个受保护任务结束/失败/取消后，停止 Service
///
/// 保护范围：
/// - 只有明确注册为"需要持续后台保护"的 task type 才启动 Service
/// - 其他 task type 不进入 TaskProtectionManager 计数
class TaskProtectionManager {
  TaskProtectionManager._();

  static final TaskProtectionManager instance = TaskProtectionManager._();

  static const MethodChannel _channel = MethodChannel(
    'com.ruyi.azruiyoi/task_protection',
  );

  /// 当前受保护的任务计数
  int _protectedTaskCount = 0;

  /// Service 是否正在运行
  bool _serviceRunning = false;

  /// 需要保护的任务类型及其通知文案
  /// 只有在此 Map 中注册的任务类型才会启动 Foreground Service
  ///
  /// chat_generation 不使用 FGS（普通聊天生成通常只有几秒到几十秒，不需要强后台保障）
  /// 未来其他确实需要长时间持续执行的 task type 可以在这里注册
  final Map<String, String> _protectedTaskTypes = {
    // 当前无需要保护的任务类型
  };

  /// 当前活跃的受保护任务类型集合
  final Set<String> _activeTaskTypes = {};

  /// 注册需要后台保护的任务类型
  ///
  /// [taskType] 任务类型
  /// [notificationText] 该任务类型运行时的通知文案
  ///
  /// 只有注册的任务类型才会触发 Foreground Service 保护。
  void registerProtectedTaskType(String taskType, String notificationText) {
    _protectedTaskTypes[taskType] = notificationText;
  }

  /// 检查任务类型是否需要后台保护
  bool isProtected(String taskType) {
    return _protectedTaskTypes.containsKey(taskType);
  }

  /// 任务开始运行时调用
  ///
  /// [taskType] 任务类型（如 'chat_generation'）
  ///
  /// 只有已注册为需要保护的任务类型才会启动 Service。
  Future<void> onTaskStarted(String taskType) async {
    // 只处理已注册的受保护任务类型
    if (!isProtected(taskType)) {
      return;
    }

    _protectedTaskCount++;
    _activeTaskTypes.add(taskType);

    if (_protectedTaskCount == 1 && !_serviceRunning) {
      // 第一个任务，启动 Service
      await _startService();
    } else if (_protectedTaskCount > 1) {
      // 多个任务运行时，更新通知文案（如果需要）
      await _updateNotification();
    }

    if (kDebugMode) {
      print(
        'TaskProtectionManager: 任务开始 [$taskType], 当前保护任务数: $_protectedTaskCount',
      );
    }
  }

  /// 任务结束时调用（无论成功、失败还是取消）
  ///
  /// [taskType] 任务类型（如 'chat_generation'）
  Future<void> onTaskEnded(String taskType) async {
    // 只处理已注册的受保护任务类型
    if (!isProtected(taskType)) {
      return;
    }

    if (_protectedTaskCount > 0) {
      _protectedTaskCount--;
    }

    if (_protectedTaskCount == 0 && _serviceRunning) {
      // 最后一个任务结束，停止 Service
      _activeTaskTypes.clear();
      await _stopService();
    } else if (_protectedTaskCount > 0) {
      // 还有其他任务在运行，可能需要更新通知
      await _updateNotification();
    }

    if (kDebugMode) {
      print(
        'TaskProtectionManager: 任务结束 [$taskType], 当前保护任务数: $_protectedTaskCount',
      );
    }
  }

  /// 启动 Foreground Service
  Future<void> _startService() async {
    try {
      // 获取当前应该显示的通知文案
      final notificationText = _getCurrentNotificationText();

      final result = await _channel.invokeMethod('startTaskProtection', {
        'notificationText': notificationText,
      });

      if (result == true) {
        _serviceRunning = true;
        if (kDebugMode) {
          print('TaskProtectionManager: Service 已启动');
        }
      }
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('TaskProtectionManager: 启动 Service 失败: ${e.message}');
      }
    }
  }

  /// 停止 Foreground Service
  Future<void> _stopService() async {
    try {
      final result = await _channel.invokeMethod('stopTaskProtection');
      if (result == true) {
        _serviceRunning = false;
        if (kDebugMode) {
          print('TaskProtectionManager: Service 已停止');
        }
      }
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('TaskProtectionManager: 停止 Service 失败: ${e.message}');
      }
    }
  }

  /// 更新通知文案
  ///
  /// 当有多个任务类型同时运行时，可能需要更新通知显示。
  /// 当前策略：显示第一个活跃任务类型的文案。
  Future<void> _updateNotification() async {
    if (!_serviceRunning) return;

    try {
      final notificationText = _getCurrentNotificationText();
      await _channel.invokeMethod('updateNotification', {
        'notificationText': notificationText,
      });
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('TaskProtectionManager: 更新通知失败: ${e.message}');
      }
    }
  }

  /// 获取当前应该显示的通知文案
  String _getCurrentNotificationText() {
    // 优先显示 chat_generation 的文案
    if (_activeTaskTypes.contains('chat_generation')) {
      return _protectedTaskTypes['chat_generation']!;
    }

    // 否则显示第一个活跃任务类型的文案
    if (_activeTaskTypes.isNotEmpty) {
      final firstType = _activeTaskTypes.first;
      return _protectedTaskTypes[firstType]!;
    }

    // 理论上不应该到达这里，因为只有受保护的任务才会启动 Service
    return '正在处理任务';
  }

  /// 重置状态（用于测试或异常恢复）
  @visibleForTesting
  void reset() {
    _protectedTaskCount = 0;
    _serviceRunning = false;
    _activeTaskTypes.clear();
  }
}
