library;

import 'dart:convert';

import '../local_job.dart';
import '../local_job_service.dart';

const String kGroupRoundTaskType = 'group_round';

class GroupRoundTaskPayload {
  const GroupRoundTaskPayload({required this.roomId, required this.roundId});

  final String roomId;
  final String roundId;

  Map<String, Object?> toJson() => {'room_id': roomId, 'round_id': roundId};

  String toJsonString() => jsonEncode(toJson());

  factory GroupRoundTaskPayload.fromJsonString(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map) throw const FormatException('群轮次任务格式错误');
    final roomId = decoded['room_id'];
    final roundId = decoded['round_id'];
    if (roomId is! String ||
        roomId.isEmpty ||
        roundId is! String ||
        roundId.isEmpty) {
      throw const FormatException('群轮次任务缺少房间或轮次');
    }
    return GroupRoundTaskPayload(roomId: roomId, roundId: roundId);
  }
}

Future<LocalJob> createGroupRoundJob({
  required LocalJobService jobService,
  required String roomId,
  required String roundId,
  required int totalSteps,
}) => jobService.create(
  taskType: kGroupRoundTaskType,
  payload: GroupRoundTaskPayload(
    roomId: roomId,
    roundId: roundId,
  ).toJsonString(),
  totalItems: totalSteps,
  scopeType: 'group_room',
  scopeId: roomId,
);
