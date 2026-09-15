part of 'local_chat_service.dart';

final class _GameOfferState {
  _GameOfferState(this._strategy);

  final ChatGameStrategy? _strategy;
  bool attempted = false;
  bool succeeded = false;
  bool failed = false;

  void record({required String toolName, required ToolResult result}) {
    final strategy = _strategy;
    if (strategy == null || toolName != strategy.offerToolName) return;
    attempted = true;
    if (!result.isSuccess) {
      failed = true;
      return;
    }
    final text = result.data?['text'];
    try {
      final payload = text is String ? jsonDecode(text) : null;
      final status = payload is Map ? payload['status'] : null;
      if (status == 'accepted' || status == 'pending_user_decision') {
        succeeded = true;
      } else {
        failed = true;
      }
    } catch (_) {
      failed = true;
    }
  }
}
