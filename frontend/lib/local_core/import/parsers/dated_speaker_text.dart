import 'dart:convert';

class DatedSpeakerTextHeader {
  const DatedSpeakerTextHeader({
    required this.speaker,
    required this.timestamp,
  });

  final String speaker;
  final String timestamp;
}

final _datedSpeakerHeader = RegExp(
  r'^(\d{4})年(\d{1,2})月(\d{1,2})日 (\d{1,2}):(\d{2}):(\d{2}) · ([^\r\n]{1,40})$',
);

DatedSpeakerTextHeader? parseDatedSpeakerTextHeader(String line) {
  final match = _datedSpeakerHeader.firstMatch(line.trim());
  if (match == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  if (parts.first < 1) return null;
  final date = DateTime.utc(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  );
  final normalized = [
    date.year,
    date.month,
    date.day,
    date.hour,
    date.minute,
    date.second,
  ];
  for (var i = 0; i < parts.length; i++) {
    if (parts[i] != normalized[i]) return null;
  }
  final speaker = match.group(7)!.trim();
  if (speaker.isEmpty) return null;
  return DatedSpeakerTextHeader(
    speaker: speaker,
    timestamp:
        '${match.group(1)}-${match.group(2)!.padLeft(2, '0')}-'
        '${match.group(3)!.padLeft(2, '0')}T'
        '${match.group(4)!.padLeft(2, '0')}:${match.group(5)}:${match.group(6)}',
  );
}

bool isDatedSpeakerTextTitle(String line) {
  final title = line.trim();
  return title.isNotEmpty &&
      title.length <= 120 &&
      !RegExp(r'[:：\t\r\n]').hasMatch(title) &&
      !RegExp(r'^[#▶<>`\[\]【】=~_\-]').hasMatch(title);
}

bool hasDatedSpeakerTextPrefix(String sample) {
  var hasTitle = false;
  for (final input in const LineSplitter().convert(sample)) {
    final line = input.replaceFirst(RegExp(r'^\uFEFF'), '').trim();
    if (line.isEmpty) continue;
    if (parseDatedSpeakerTextHeader(line) != null) return true;
    if (hasTitle || !isDatedSpeakerTextTitle(line)) return false;
    hasTitle = true;
  }
  return false;
}
