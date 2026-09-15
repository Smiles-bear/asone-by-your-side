import 'package:sqflite/sqflite.dart';

import '../models/assistant.dart';

class AssistantProjectionRepository {
  const AssistantProjectionRepository(this._database);

  final DatabaseExecutor _database;

  Future<List<Assistant>> list() async {
    final rows = await _database.rawQuery(
      '${_selectSql()}\nORDER BY a.created_at ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<Assistant?> get(String assistantId) async {
    final rows = await _database.rawQuery(
      '${_selectSql()}\nAND a.id = ?\nLIMIT 1',
      [assistantId],
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  String _selectSql() => '''
    SELECT a.*,
      primary_binding.model_service_id AS projected_primary_service_id,
      primary_service.model AS projected_main_model,
      vision_binding.model_service_id AS projected_vision_service_id,
      vision_service.model AS projected_assistant_model
    FROM assistants a
    LEFT JOIN assistant_model_bindings primary_binding
      ON primary_binding.assistant_id = a.id
     AND primary_binding.binding_role = 'primary'
    LEFT JOIN model_services primary_service
      ON primary_service.id = primary_binding.model_service_id
    LEFT JOIN assistant_model_bindings vision_binding
      ON vision_binding.assistant_id = a.id
     AND vision_binding.binding_role = 'auxiliary:vision'
    LEFT JOIN model_services vision_service
      ON vision_service.id = vision_binding.model_service_id
    WHERE a.import_pending = 0
  ''';

  Assistant _fromRow(Map<String, Object?> row) {
    final hydrated = Map<String, dynamic>.from(row);
    final primaryId = row['projected_primary_service_id'] as String?;
    final visionId = row['projected_vision_service_id'] as String?;
    if (primaryId?.isNotEmpty == true) {
      hydrated['model_service_id'] = primaryId;
      hydrated['main_model'] = row['projected_main_model'] as String? ?? '';
    }
    if (visionId?.isNotEmpty == true) {
      hydrated['assistant_model_service_id'] = visionId;
      hydrated['assistant_model'] =
          row['projected_assistant_model'] as String? ?? '';
    }
    return Assistant.fromJson(hydrated);
  }
}
