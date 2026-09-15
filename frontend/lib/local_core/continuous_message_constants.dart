// 连续消息功能共享常量定义

/// 回复方式常量
const kReplyModeComplete = 'complete';
const kReplyModeContinuous = 'continuous';

/// 连续消息模式 Prompt
///
/// 约束回复风格：简短、自然、即时聊天风格。
/// 不要求模型输出特殊分隔符，系统自动根据标点分段。
const kContinuousPrompt =
    '[回复方式：连续消息]'
    '请像即时聊天一样自然、简短地回复。优先使用短句，避免一次输出很长的段落；'
    '根据当前对话自然决定回复长度。不要输出任何用于分段的特殊标记，消息分段由系统处理。';
