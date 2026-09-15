import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class PublicLinkReadException implements Exception {
  const PublicLinkReadException(this.message, {this.requiresFile = false});

  final String message;
  final bool requiresFile;

  @override
  String toString() => message;
}

class PublicLinkContent {
  const PublicLinkContent({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

abstract class LinkSourceReader {
  Future<PublicLinkContent> read(Uri uri);
}

class HttpPublicLinkSourceReader implements LinkSourceReader {
  HttpPublicLinkSourceReader({
    HttpClient? client,
    this.maximumBytes = 128 * 1024 * 1024,
    this.maximumRedirects = 3,
  }) : _client = client ?? HttpClient();

  final HttpClient _client;
  final int maximumBytes;
  final int maximumRedirects;

  @override
  Future<PublicLinkContent> read(Uri uri) async {
    _validateUri(uri);
    var current = uri;
    for (var redirects = 0; redirects <= maximumRedirects; redirects++) {
      final request = await _client
          .getUrl(current)
          .timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/json, text/plain, text/markdown, text/html, application/zip',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'Azruiyoi-Mobile/1.0');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (_isRedirect(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null || redirects == maximumRedirects) {
          throw const PublicLinkReadException('公开链接重定向过多，请改用文件导入');
        }
        current = current.resolve(location);
        _validateUri(current);
        if (_looksLikeLogin(current)) {
          throw const PublicLinkReadException(
            '这个链接需要登录或授权，请改用导出的文件',
            requiresFile: true,
          );
        }
        continue;
      }
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        await response.drain<void>();
        throw const PublicLinkReadException(
          '这个链接需要登录或授权，请改用导出的文件',
          requiresFile: true,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw PublicLinkReadException('公开链接读取失败（${response.statusCode}）');
      }
      final declaredLength = response.contentLength;
      if (declaredLength > maximumBytes) {
        await response.drain<void>();
        throw const PublicLinkReadException('链接内容过大，请改用文件导入');
      }
      final builder = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in response) {
        received += chunk.length;
        if (received > maximumBytes) {
          throw const PublicLinkReadException('链接内容过大，请改用文件导入');
        }
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      final contentType = response.headers.contentType?.mimeType ?? '';
      if (_looksLikeLogin(current) ||
          (contentType == 'text/html' && _bodyLooksLikeLogin(bytes))) {
        throw const PublicLinkReadException(
          '这个链接需要登录或授权，请改用导出的文件',
          requiresFile: true,
        );
      }
      return PublicLinkContent(
        name: _sourceName(current, contentType),
        bytes: bytes,
      );
    }
    throw const PublicLinkReadException('公开链接读取失败');
  }

  void _validateUri(Uri uri) {
    if (!uri.hasScheme ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const PublicLinkReadException('请输入有效的公开链接');
    }
    final host = uri.host.toLowerCase();
    final address = InternetAddress.tryParse(host);
    if (host == 'localhost' ||
        host.endsWith('.local') ||
        (address != null && _isPrivateAddress(address))) {
      throw const PublicLinkReadException('仅支持互联网公开链接，请改用文件导入');
    }
  }

  bool _isPrivateAddress(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal) return true;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return bytes[0] == 10 ||
          bytes[0] == 127 ||
          (bytes[0] == 169 && bytes[1] == 254) ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168);
    }
    return bytes.every((byte) => byte == 0) || address.address == '::1';
  }

  bool _looksLikeLogin(Uri uri) {
    final value = '${uri.path} ${uri.query}'.toLowerCase();
    return const [
      'login',
      'signin',
      'sign-in',
      'authorize',
      'oauth',
      'account',
    ].any(value.contains);
  }

  bool _bodyLooksLikeLogin(Uint8List bytes) {
    final length = bytes.length > 32768 ? 32768 : bytes.length;
    final sample = String.fromCharCodes(bytes.take(length)).toLowerCase();
    return sample.contains('type="password"') ||
        sample.contains("type='password'") ||
        (sample.contains('<form') &&
            (sample.contains('sign in') || sample.contains('log in')));
  }

  String _sourceName(Uri uri, String contentType) {
    var name = uri.pathSegments.isEmpty ? 'shared-chat' : uri.pathSegments.last;
    if (name.isEmpty || !name.contains('.')) {
      final extension = switch (contentType) {
        'application/json' => '.json',
        'application/zip' => '.zip',
        'text/markdown' => '.md',
        'text/html' => '.html',
        _ => '.txt',
      };
      name = 'shared-chat$extension';
    }
    return name;
  }

  bool _isRedirect(int statusCode) =>
      const {301, 302, 303, 307, 308}.contains(statusCode);
}
