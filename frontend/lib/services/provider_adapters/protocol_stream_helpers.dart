part of 'protocol_client.dart';

extension on ProtocolClient {
  Future<String> _readStreamErrorBody(ResponseBody? body) async {
    if (body == null) return '';
    final bytes = BytesBuilder(copy: false);
    const maximumBytes = 8 * 1024;
    await for (final chunk in body.stream) {
      final remaining = maximumBytes - bytes.length;
      if (remaining <= 0) break;
      bytes.add(
        chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
      );
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true).trim();
  }
}
