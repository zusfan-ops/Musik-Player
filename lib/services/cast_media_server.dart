import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Lightweight embedded HTTP server so local audio files on the device can be
/// streamed to Chromecast and Google Nest speakers over the local Wi-Fi LAN.
class CastMediaServer {
  HttpServer? _server;
  String? _activeFilePath;
  String _activeToken = '';

  bool get isRunning => _server != null;

  Future<String?> serveLocalFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    if (_server == null) {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _server!.listen(_handleRequest);
    }

    _activeFilePath = filePath;
    _activeToken = DateTime.now().millisecondsSinceEpoch.toString();

    final lanIp = await _resolveLanIp();
    if (lanIp == null) return null;
    final ext = p.extension(filePath).toLowerCase();
    return 'http://$lanIp:${_server!.port}/cast_$_activeToken$ext';
  }

  static String mimeTypeForPath(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.mp3':
        return 'audio/mpeg';
      case '.m4a':
      case '.aac':
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
      final path = _activeFilePath;
      if (path == null || !request.uri.path.contains(_activeToken)) {
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
