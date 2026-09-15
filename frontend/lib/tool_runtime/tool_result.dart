/// 工具执行结果
///
/// 本文件定义了工具执行的结果结构，包括执行状态、返回数据、错误信息等。
library;

import 'dart:convert';

import 'package:collection/collection.dart';

/// 工具执行状态枚举
///
/// 表示工具执行的最终状态。
enum ToolResultStatus {
  /// 执行成功
  success,

  /// 执行失败（工具内部错误）
  error,

  /// 执行被取消（用户或系统主动取消）
  cancelled,

  /// 执行超时（超过设定的时间限制）
  timeout,

  /// 部分成功（部分操作成功，部分失败）
  partial,

  /// 需要确认（高风险操作需要用户确认）
  requireConfirmation,
}

/// 工具执行结果
///
/// 封装工具执行的完整结果信息，包括状态、数据、错误信息和执行时长。
///
/// 使用示例：
/// ```dart
/// // 成功结果
/// final successResult = ToolResult.success(
///   data: {'timestamp': DateTime.now().toIso8601String()},
///   executionTimeMs: 150,
/// );
///
/// // 错误结果
/// final errorResult = ToolResult.error(
///   errorCode: 'NETWORK_ERROR',
///   errorMessage: '无法连接到服务器',
///   executionTimeMs: 5000,
/// );
///
/// // 检查结果
/// if (result.isSuccess) {
///   print('执行成功: ${result.data}');
/// } else {
///   print('执行失败: ${result.errorMessage}');
/// }
/// ```
class ToolResult {
  /// 执行状态
  final ToolResultStatus status;

  /// 结果数据（成功时包含返回数据，失败时可能为 null）
  final Map<String, dynamic>? data;

  /// 错误码（失败时提供，用于程序化处理）
  final String? errorCode;

  /// 错误信息（失败时提供，用于用户展示）
  final String? errorMessage;

  /// 执行时长（毫秒）
  final int executionTimeMs;

  /// 是否需要重试（用于可重试的错误）
  final bool retryable;

  /// 确认提示信息（当 status 为 requireConfirmation 时使用）
  final String? confirmationMessage;

  /// 创建工具执行结果
  ///
  /// 通常使用工厂方法（success/error/cancelled/timeout）创建实例，
  /// 而不是直接调用构造函数。
  const ToolResult({
    required this.status,
    this.data,
    this.errorCode,
    this.errorMessage,
    required this.executionTimeMs,
    this.retryable = false,
    this.confirmationMessage,
  });

  /// 创建成功结果
  ///
  /// [data] 工具返回的数据
  /// [executionTimeMs] 执行时长（毫秒）
  factory ToolResult.success({
    required Map<String, dynamic> data,
    required int executionTimeMs,
  }) {
    return ToolResult(
      status: ToolResultStatus.success,
      data: data,
      executionTimeMs: executionTimeMs,
    );
  }

  /// 创建错误结果
  ///
  /// [errorCode] 错误码（用于程序化处理）
  /// [errorMessage] 错误信息（用于用户展示）
  /// [executionTimeMs] 执行时长（毫秒）
  /// [retryable] 是否可重试（默认 false）
  factory ToolResult.error({
    required String errorCode,
    required String errorMessage,
    required int executionTimeMs,
    bool retryable = false,
    Map<String, dynamic>? data,
  }) {
    return ToolResult(
      status: ToolResultStatus.error,
      data: data,
      errorCode: errorCode,
      errorMessage: errorMessage,
      executionTimeMs: executionTimeMs,
      retryable: retryable,
    );
  }

  /// 创建取消结果
  ///
  /// [executionTimeMs] 执行时长（毫秒，取消前的执行时间）
  factory ToolResult.cancelled({required int executionTimeMs}) {
    return ToolResult(
      status: ToolResultStatus.cancelled,
      errorCode: 'CANCELLED',
      errorMessage: '工具执行已取消',
      executionTimeMs: executionTimeMs,
    );
  }

  /// 创建超时结果
  ///
  /// [executionTimeMs] 执行时长（毫秒，即超时时间）
  factory ToolResult.timeout({required int executionTimeMs}) {
    return ToolResult(
      status: ToolResultStatus.timeout,
      errorCode: 'TIMEOUT',
      errorMessage: '工具执行超时',
      executionTimeMs: executionTimeMs,
      retryable: true,
    );
  }

  /// 创建需要确认结果
  ///
  /// [confirmationMessage] 确认提示信息
  /// [data] 工具返回的数据（用于展示）
  /// [executionTimeMs] 执行时长（毫秒）
  factory ToolResult.requireConfirmation({
    required String confirmationMessage,
    Map<String, dynamic>? data,
    required int executionTimeMs,
  }) {
    return ToolResult(
      status: ToolResultStatus.requireConfirmation,
      data: data,
      confirmationMessage: confirmationMessage,
      executionTimeMs: executionTimeMs,
    );
  }

  /// 创建部分成功结果
  ///
  /// [data] 部分成功的数据
  /// [errorMessage] 失败部分的说明
  /// [executionTimeMs] 执行时长（毫秒）
  factory ToolResult.partial({
    required Map<String, dynamic> data,
    String? errorMessage,
    required int executionTimeMs,
  }) {
    return ToolResult(
      status: ToolResultStatus.partial,
      data: data,
      errorMessage: errorMessage,
      executionTimeMs: executionTimeMs,
    );
  }

  /// 检查是否执行成功
  bool get isSuccess => status == ToolResultStatus.success;

  /// 检查是否执行失败
  bool get isError => status == ToolResultStatus.error;

  /// 检查是否被取消
  bool get isCancelled => status == ToolResultStatus.cancelled;

  /// 检查是否超时
  bool get isTimeout => status == ToolResultStatus.timeout;

  /// 检查是否需要确认
  bool get isRequireConfirmation =>
      status == ToolResultStatus.requireConfirmation;

  /// 检查是否部分成功
  bool get isPartial => status == ToolResultStatus.partial;

  /// 转换为 JSON 对象
  Map<String, dynamic> toJson() {
    return {
      'status': status.name,
      if (data != null) 'data': data,
      if (errorCode != null) 'errorCode': errorCode,
      if (errorMessage != null) 'errorMessage': errorMessage,
      'executionTimeMs': executionTimeMs,
      'retryable': retryable,
      if (confirmationMessage != null)
        'confirmationMessage': confirmationMessage,
    };
  }

  /// 从 JSON 对象创建
  factory ToolResult.fromJson(Map<String, dynamic> json) {
    final statusStr = json['status'] as String;
    final status = ToolResultStatus.values.firstWhere(
      (e) => e.name == statusStr,
      orElse: () => throw ArgumentError('Unknown status: $statusStr'),
    );

    return ToolResult(
      status: status,
      data: json['data'] as Map<String, dynamic>?,
      errorCode: json['errorCode'] as String?,
      errorMessage: json['errorMessage'] as String?,
      executionTimeMs: json['executionTimeMs'] as int,
      retryable: json['retryable'] as bool? ?? false,
      confirmationMessage: json['confirmationMessage'] as String?,
    );
  }

  /// 转换为 JSON 字符串
  String toJsonString() {
    return jsonEncode(toJson());
  }

  /// 从 JSON 字符串创建
  factory ToolResult.fromJsonString(String jsonString) {
    return ToolResult.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  /// 转换为模型可读的内容字符串
  ///
  /// 用于将结果传递给 AI 模型，模型会根据状态决定如何处理。
  String toModelContent() {
    switch (status) {
      case ToolResultStatus.success:
      case ToolResultStatus.partial:
        return jsonEncode(data ?? {});
      case ToolResultStatus.error:
      case ToolResultStatus.timeout:
      case ToolResultStatus.cancelled:
        return jsonEncode({
          'error': true,
          'errorCode': errorCode,
          'errorMessage': errorMessage,
          'retryable': retryable,
        });
      case ToolResultStatus.requireConfirmation:
        return jsonEncode({
          'requireConfirmation': true,
          'message': confirmationMessage,
          if (data != null) 'data': data,
        });
    }
  }

  @override
  String toString() {
    final buffer = StringBuffer('ToolResult(');
    buffer.write('status: ${status.name}');

    if (data != null) {
      buffer.write(', data: $data');
    }

    if (errorCode != null) {
      buffer.write(', errorCode: $errorCode');
    }

    if (errorMessage != null) {
      buffer.write(', errorMessage: $errorMessage');
    }

    buffer.write(', executionTimeMs: $executionTimeMs');

    if (retryable) {
      buffer.write(', retryable: true');
    }

    if (confirmationMessage != null) {
      buffer.write(', confirmationMessage: $confirmationMessage');
    }

    buffer.write(')');
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ToolResult) return false;

    // 使用 DeepCollectionEquality 进行 Map 深度比较
    const mapEquality = DeepCollectionEquality();

    return status == other.status &&
        mapEquality.equals(data, other.data) &&
        errorCode == other.errorCode &&
        errorMessage == other.errorMessage &&
        executionTimeMs == other.executionTimeMs &&
        retryable == other.retryable &&
        confirmationMessage == other.confirmationMessage;
  }

  @override
  int get hashCode {
    // 使用 DeepCollectionEquality 计算 Map 的 hashCode
    const mapEquality = DeepCollectionEquality();

    return Object.hash(
      status,
      mapEquality.hash(data),
      errorCode,
      errorMessage,
      executionTimeMs,
      retryable,
      confirmationMessage,
    );
  }
}
