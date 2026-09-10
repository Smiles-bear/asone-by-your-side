import 'package:asone_contracts/asone_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OpenCoreBinding serves the attached core until detached', () {
    expect(() => OpenCoreBinding.instance, throwsStateError);

    final core = _FakeOpenCore();
    OpenCoreBinding.attach(core);
    addTearDown(OpenCoreBinding.detach);

    expect(OpenCoreBinding.instance, same(core));

    OpenCoreBinding.detach();
    expect(() => OpenCoreBinding.instance, throwsStateError);
  });
}

class _FakeOpenCore implements OpenCore {
  @override
  AssistantRepositoryApi get assistants => throw UnimplementedError();

  @override
  ConversationRepositoryApi get conversations => throw UnimplementedError();

  @override
  ModelServiceRepositoryApi get modelServices => throw UnimplementedError();

  @override
  CalendarRepositoryApi get calendar => throw UnimplementedError();

  @override
  StickyNoteRepositoryApi get stickyNotes => throw UnimplementedError();

  @override
  MessageBoardRepositoryApi get messageBoard => throw UnimplementedError();

  @override
  FeatureUnreadApi get featureUnread => throw UnimplementedError();

  @override
  TokenUsageApi get tokenUsage => throw UnimplementedError();
}
