import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Lightweight embedded HTTP server & proxy so both local audio files and
/// header-authenticated remote streams (e.g. YouTube/M3U) can be played on
/// Chromecast and Google Nest speakers over the local Wi-Fi LAN.
class CastMediaServer {
  HttpServer? _server;
  String? _activeFilePath;
  String? _activeRemoteUrl;
  Map<String, String> _activeRemoteHeaders = const {};
  String _activeRemoteMime = 'audio/mp4';
  String _activeToken = '';

  bool get isRunning => _server != null;

  Future<void> _ensureServer() async {
    if (_server == null) {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _server!.listen(_handleRequest);
    }
  }

  Future<String?> serveLocalFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    await _ensureServer();
    _activeFilePath = filePath;
    _activeRemoteUrl = null;
    _activeRemoteHeaders = const {};
    _activeToken = DateTime.now().millisecondsSinceEpoch.toString();

    final lanIp = await _resolveLanIp();
    if (lanIp == null) return null;
    final ext = p.extension(filePath).toLowerCase();
    return 'http://$lanIp:${_server!.port}/cast_$_activeToken$ext';
  }

  Future<String?> serveRemoteProxy(
    String remoteUrl,
    Map<String, String> headers, {
    String mimeType = 'audio/mp4',
  }) async {
    if (remoteUrl.trim().isEmpty) return null;
    await _ensureServer();
    _activeFilePath = null;
    _activeRemoteUrl = remoteUrl;
    _activeRemoteHeaders = Map<String, String>.from(headers);
    _activeRemoteMime = mimeType;
    _activeToken = DateTime.now().millisecondsSinceEpoch.toString();

    final lanIp = await _resolveLanIp();
    if (lanIp == null) return null;
    return 'http://$lanIp:${_server!.port}/proxy_$_activeToken.mp4';
  }

  static String mimeTypeForPath(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.mp3':
        return 'audio/mpeg';
      case '.m4a':
      case '.aac':
      case '.mp4':
        return 'audio/mp4';
      case '.flac':
        return 'audio/flac';
      case '.ogg':
      case '.opus':
        return 'audio/ogg';
      case '.wav':
        return 'audio/wav';
      default:
        return 'audio/mpeg';
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (!request.uri.path.contains(_activeToken)) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      if (_activeRemoteUrl != null) {
        await _proxyRemoteStream(request, _activeRemoteUrl!);
        return;
      }

      final path = _activeFilePath;
      if (path == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final file = File(path);
      if (!await file.exists()) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final totalLength = await file.length();
      final mime = mimeTypeForPath(path);
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(HttpHeaders.contentTypeHeader, mime);

      if (totalLength == 0) {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentLength = 0;
        await request.response.close();
        return;
      }

      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final spec = rangeHeader.substring(6).split('-');
        final start = int.tryParse(spec[0]) ?? 0;
        final end = (spec.length > 1 && spec[1].isNotEmpty)
            ? (int.tryParse(spec[1]) ?? totalLength - 1)
            : totalLength - 1;
        final safeStart = start.clamp(0, totalLength - 1);
        final safeEnd = end.clamp(safeStart, totalLength - 1);
        final chunkLen = safeEnd - safeStart + 1;

        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $safeStart-$safeEnd/$totalLength',
        );
        request.response.headers.contentLength = chunkLen;
        await request.response.addStream(file.openRead(safeStart, safeEnd + 1));
      } else {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentLength = totalLength;
        await request.response.addStream(file.openRead());
      }
      await request.response.close();
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _proxyRemoteStream(HttpRequest request, String remoteUrl) async {
    final client = http.Client();
    try {
      final upstreamReq = http.Request('GET', Uri.parse(remoteUrl));
      upstreamReq.headers.addAll(_activeRemoteHeaders);
      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      if (rangeHeader != null && rangeHeader.isNotEmpty) {
        upstreamReq.headers['Range'] = rangeHeader;
      }

      final upstreamRes = await client.send(upstreamReq);
      request.response.statusCode = upstreamRes.statusCode;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        upstreamRes.headers['content-type'] ?? _activeRemoteMime,
      );
      final contentLen = upstreamRes.headers['content-length'];
      if (contentLen != null) {
        final parsed = int.tryParse(contentLen);
        if (parsed != null) request.response.headers.contentLength = parsed;
      }
      final contentRange = upstreamRes.headers['content-range'];
      if (contentRange != null) {
        request.response.headers.set(HttpHeaders.contentRangeHeader, contentRange);
      }

      await request.response.addStream(upstreamRes.stream);
      await request.response.close();
    } finally {
      client.close();
    }
  }

  Future<String?> _resolveLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && !addr.address.startsWith('169.254.')) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> dispose() async {
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
  }
}
