# asone_contracts

Azruiyoi 的公开数据模型与跨模块契约包。

本包只包含可公开分发的模型、序列化规则和稳定接口，不包含记忆、上下文编排、模型绑定或其他产品核心实现。公开仓库中的 UI、示例实现和测试可以依赖本包；正式产品通过内部包提供闭源实现。

## 当前内容

### 数据模型

- `Assistant`
- `Conversation`
- `AssistantWithConversation`
- `BoardPostLikeState`, `BoardPostItem`, `BoardCommentItem`
- `CalendarEventItem`, `CalendarEventInput`, `CalendarOccurrence`, `CalendarDeletionVerification`
- `ModelService`
- `PendingItem`
- `SearchResult`
- `StickyNoteItem`, `StickyNoteChecklistItem`, `StickyNoteDetail`, `StickyNoteChecklistDraft`
- `FeatureUnreadKind`, `FeatureUnreadSnapshot`
- `TokenUsageSummary`, `DailyTokenUsage`, `TokenUsageRecord`

模型保留现有 JSON 字段和默认值，确保覆盖安装、数据迁移和私有实现替换时保持兼容。

### 公开接口

- `AssistantRepositoryApi`, `ConversationRepositoryApi`, `ModelServiceRepositoryApi`
- `CalendarRepositoryApi`, `StickyNoteRepositoryApi`, `MessageBoardRepositoryApi`
- `FeatureUnreadApi`, `TokenUsageApi`
- `OpenCore`（公开能力接口聚合）与 `OpenCoreBinding`（启动绑定点）

数据模型为纯 Dart；接口除 `FeatureUnreadApi.changes`（`ValueListenable`，依赖 `flutter/foundation`）外均为纯 Dart 契约。各版本在启动时通过 `OpenCoreBinding.attach(...)` 绑定自己的实现，UI 代码只依赖本包中的接口类型；聊天收发、消息操作与 token 记录写入（`recordUsage`）不在本包范围内。
