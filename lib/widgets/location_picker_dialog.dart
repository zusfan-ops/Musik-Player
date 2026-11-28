import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../theme/app_theme.dart';

class PlaceSuggestion {
  final String displayName;
  final double lat;
  final double lng;

  const PlaceSuggestion({
    required this.displayName,
    required this.lat,
    required this.lng,
  });
}

class OsmNominatimHelper {
  static const Map<String, String> _headers = {
    'User-Agent': 'MediaCenterApp/1.13 (https://mediacenter.ordr.my.id)',
    'Accept': 'application/json',
  };

  static Future<List<PlaceSuggestion>> searchPlaces(String query) async {
    final q = query.trim();
    if (q.length < 3) return const [];
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': q,
        'format': 'json',
        'limit': '6',
        'addressdetails': '1',
      });
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return const [];
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) {
            final lat = double.tryParse(m['lat']?.toString() ?? '');
            final lng = double.tryParse(m['lon']?.toString() ?? '');
            final name = m['display_name']?.toString() ?? '';
            if (lat == null || lng == null || name.isEmpty) return null;
            return PlaceSuggestion(displayName: name, lat: lat, lng: lng);
          })
          .whereType<PlaceSuggestion>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': lat.toStringAsFixed(6),
        'lon': lng.toStringAsFixed(6),
        'format': 'json',
      });
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map) {
        return decoded['display_name']?.toString();
      }
    } catch (_) {}
    return null;
  }
}

/// Interactive OpenStreetMap tile picker with search autocomplete,
/// pan-by-drag, zoom controls, and reverse geocoding (Android & Windows).
Future<PlaceSuggestion?> showMapLocationPickerDialog(
  BuildContext context, {
  double? initialLat,
  double? initialLng,
  String? initialAddress,
}) async {
  return showDialog<PlaceSuggestion>(
    context: context,
    builder: (_) => _MapLocationPickerDialog(
      initialLat: initialLat ?? -6.200000,
      initialLng: initialLng ?? 106.816666,
      initialAddress: initialAddress ?? '',
    ),
  );
}

class _MapLocationPickerDialog extends StatefulWidget {
  const _MapLocationPickerDialog({
    required this.initialLat,
    required this.initialLng,
    required this.initialAddress,
  });

  final double initialLat;
  final double initialLng;
  final String initialAddress;

  @override
  State<_MapLocationPickerDialog> createState() =>
      _MapLocationPickerDialogState();
}

class _MapLocationPickerDialogState extends State<_MapLocationPickerDialog> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<PlaceSuggestion> _suggestions = const [];
  bool _searching = false;
  bool _resolvingAddress = false;

  late double _lat;
  late double _lng;
  late String _address;
  int _zoom = 15;

  @override
  void initState() {
    super.initState();
    _lat = widget.initialLat;
    _lng = widget.initialLng;
    _address = widget.initialAddress;
    if (_address.isNotEmpty) {
      _searchCtrl.text = _address;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      if (value.trim().length < 3) {
        setState(() => _suggestions = const []);
        return;
      }
      setState(() => _searching = true);
      final list = await OsmNominatimHelper.searchPlaces(value);
      if (!mounted) return;
      setState(() {
        _suggestions = list;
        _searching = false;
      });
    });
  }

  void _panByPixels(double dx, double dy) {
    final scale = math.pow(2, _zoom).toDouble() * 256.0;
    final worldX = ((_lng + 180.0) / 360.0) * scale - dx;
    final sinLat = math.sin(_lat * math.pi / 180.0).clamp(-0.9999, 0.9999);
    final worldY =
        (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) * scale -
            dy;

    final newLng = ((worldX / scale) * 360.0 - 180.0).clamp(-180.0, 180.0);
    final n = math.pi - 2 * math.pi * (worldY / scale);
    final newLat =
        (180.0 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n))))
            .clamp(-85.0, 85.0);

    setState(() {
      _lat = newLat;
      _lng = newLng;
    });
  }

  Future<void> _confirmLocation() async {
    setState(() => _resolvingAddress = true);
    final resolved = await OsmNominatimHelper.reverseGeocode(_lat, _lng);
    if (!mounted) return;
    setState(() => _resolvingAddress = false);
    Navigator.of(context).pop(
      PlaceSuggestion(
        displayName: resolved ??
            (_address.isNotEmpty
                ? _address
                : '${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}'),
        lat: _lat,
        lng: _lng,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = math.pow(2, _zoom).toInt();
    final exactTileX = ((_lng + 180.0) / 360.0) * n;
    final latRad = _lat * math.pi / 180.0;
    final exactTileY =
        (1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) /
            2.0 *
            n;

    final centerTileX = exactTileX.floor();
    final centerTileY = exactTileY.floor();
    final fracX = exactTileX - centerTileX;
    final fracY = exactTileY - centerTileY;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.map_rounded, color: Color(0xFF0284C7)),
          SizedBox(width: 8),
          Expanded(child: Text('Pilih Lokasi Toko di Peta')),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  labelText: 'Cari alamat / nama tempat',
                  hintText: 'Ketik alamat atau nama jalan...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_suggestions.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 160),
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: AppColors.card(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.highlight(context)),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, idx) {
                      final s = _suggestions[idx];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.location_on_outlined, size: 18),
                        title: Text(
                          s.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        onTap: () {
                          setState(() {
                            _lat = s.lat;
                            _lng = s.lng;
                            _address = s.displayName;
                            _searchCtrl.text = s.displayName;
                            _suggestions = const [];
                          });
                        },
                      );
                    },
                  ),
                ),
              const SizedBox(height: 10),
              SizedBox(
                height: 280,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LayoutBuilder(
                    builder: (ctx, constraints) {
                      final w = constraints.maxWidth;
                      final h = constraints.maxHeight;
                      const tileSize = 256.0;
                      final originLeft = w / 2 - fracX * tileSize;
                      final originTop = h / 2 - fracY * tileSize;

                      return GestureDetector(
                        onPanUpdate: (details) {
                          _panByPixels(details.delta.dx, details.delta.dy);
                        },
                        child: Stack(
                          children: [
                            Container(color: const Color(0xFF1E293B)),
                            for (int dx = -1; dx <= 1; dx++)
                              for (int dy = -1; dy <= 1; dy++)
                                Positioned(
                                  left: originLeft + dx * tileSize,
                                  top: originTop + dy * tileSize,
                                  width: tileSize,
                                  height: tileSize,
                                  child: Image.network(
                                    'https://tile.openstreetmap.org/$_zoom/${(centerTileX + dx) % n}/${(centerTileY + dy).clamp(0, n - 1)}.png',
                                    headers: const {
                                      'User-Agent':
                                          'MediaCenterApp/1.13 (https://mediacenter.ordr.my.id)',
                                    },
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                      color: const Color(0xFF334155),
                                    ),
                                  ),
                                ),
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.only(bottom: 32),
                                child: Icon(
                                  Icons.location_on_rounded,
                                  color: Color(0xFFE50914),
                                  size: 40,
                                ),
                              ),
                            ),
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: Column(
                                children: [
                                  FloatingActionButton.small(
                                    heroTag: 'osm_zoom_in',
                                    onPressed: _zoom < 18
                                        ? () => setState(() => _zoom++)
                                        : null,
                                    child: const Icon(Icons.add),
                                  ),
                                  const SizedBox(height: 6),
                                  FloatingActionButton.small(
                                    heroTag: 'osm_zoom_out',
                                    onPressed: _zoom > 4
                                        ? () => setState(() => _zoom--)
                                        : null,
                                    child: const Icon(Icons.remove),
                                  ),
                                ],
                              ),
                            ),
                            Positioned(
                              left: 8,
                              bottom: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Geser peta • ${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          onPressed: _resolvingAddress ? null : _confirmLocation,
          icon: _resolvingAddress
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: Text(_resolvingAddress ? 'Memuat Alamat...' : 'Gunakan Lokasi Ini'),
        ),
      ],
    );
  }
}
