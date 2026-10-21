/// Community requests contain only the current conversation's public text.
/// Keep system authority and message order; remove internal layout markers.
List<Map<String, Object?>> layoutPromptContext(
  List<Map<String, Object?>> source,
) => [
  for (final message in source)
    if (message['_prompt_turn_boundary_only'] != true)
      Map<String, Object?>.from(message)
        ..remove('_context_kind')
        ..remove('_prompt_turn_boundary')
        ..remove('_prompt_turn_boundary_only')
        ..remove('_prompt_scope_facts_to_turn'),
];
