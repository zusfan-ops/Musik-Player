import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:musik_m3u_player/models/music_models.dart';
import 'package:musik_m3u_player/providers/music_provider.dart';
import 'package:musik_m3u_player/services/config_backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConfigBackupService & Playlist Management', () {
    test('buildBackupJson strips local paths and parseAndPreview summarizes counts', () {
      final urlPl = M3uPlaylist(
        id: 'pl-url-1',
        name: 'TV Indonesia',
        category: 'TV & CCTV',
        sourceType: M3uSourceType.url,
        sourceLocation: 'https://iptv-org.github.io/iptv/countries/id.m3u',
        cachedM3uPath: r'C:\Users\Secret\AppData\cache.m3u',
        tracks: const [
          TrackItem(
            id: 't-url-1',
            title: 'TVRI',
            artist: 'TV',
            album: 'TV Indonesia',
            sourceType: TrackSourceType.remoteStream,
            pathOrUrl: 'https://stream.example.com/tvri.m3u8',
            offlineCachePath: r'C:\Users\Secret\offline\tvri.ts',
            directoryPath: r'C:\Users\Secret\offline',
            directoryName: 'TV Indonesia',
            artworkUrl: r'C:\Users\Secret\art.jpg',
            isVideo: true,
          ),
        ],
        updatedAt: DateTime(2026, 11, 28),
      );
      final localPl = M3uPlaylist(
        id: 'pl-local-1',
        name: 'Musik Pribadi',
        category: 'Musik',
        sourceType: M3uSourceType.file,
        sourceLocation: r'C:\Users\Secret\Music\private.m3u',
        tracks: const [],
        updatedAt: DateTime(2026, 11, 28),
      );

      final raw = ConfigBackupService.buildBackupJson(
        playlists: [urlPl, localPl],
        favoriteIds: {'fav-1', 'fav-2'},
        youtubePlaylists: const [],
        settings: {'ytAutoCacheEnabled': true, 'crossfadeSeconds': 3},
      );

      // Must not leak raw local directory path
      expect(raw.contains(r'C:\Users\Secret'), isFalse);
      expect(raw.contains('private.m3u'), isTrue);

      final preview = ConfigBackupService.parseAndPreview(raw);
      expect(preview.schemaVersion, 1);
      expect(preview.urlPlaylistCount, 1);
      expect(preview.localPlaylistCount, 1);
      expect(preview.favoriteCount, 2);
      expect(preview.settingsCount, 2);
    });

    test('parseAndPreview rejects unsupported schemaVersion', () {
      expect(
        () => ConfigBackupService.parseAndPreview(
          jsonEncode({'schemaVersion': 99}),
        ),
        throwsFormatException,
      );
    });

    test('MusicProvider supports category update, drag reorder, duplicate detection, and backup restore', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = MusicProvider(autoScanOnInit: false);
      await provider.initializeForTest();

      final preview = ConfigBackupService.parseAndPreview(
        ConfigBackupService.buildBackupJson(
          playlists: [
            M3uPlaylist(
              id: 'p1',
              name: 'Radio Satu',
              category: 'Radio',
              sourceType: M3uSourceType.url,
              sourceLocation: 'https://example.com/radio1.m3u',
              tracks: const [],
              updatedAt: DateTime(2026, 11, 28),
            ),
            M3uPlaylist(
              id: 'p2',
              name: 'Musik Santai',
              category: 'Musik',
              sourceType: M3uSourceType.url,
              sourceLocation: 'https://example.com/musik.m3u',
              tracks: const [],
              updatedAt: DateTime(2026, 11, 28),
            ),
          ],
          favoriteIds: {'track-1'},
          youtubePlaylists: const [],
          settings: {
            'ytAutoCacheEnabled': false,
            'crossfadeSeconds': 5,
            'bassBoostStrength': 0.6,
            'loudnessGainDb': 4.5,
            'eqBandGains': [1.0, 2.0, 0.0, -1.0, 3.0],
          },
        ),
      );

      final res = await provider.restoreBackup(preview, replaceExisting: false);
      expect(res.addedPlaylists, 2);
      expect(res.restoredFavorites, 1);
      expect(provider.ytAutoCacheEnabled, isFalse);
      expect(provider.bassBoostStrength, 0.6);
      expect(provider.loudnessGainDb, 4.5);
      expect(provider.eqBandGains, [1.0, 2.0, 0.0, -1.0, 3.0]);

      // Duplicate detection
      final dup = provider.findDuplicatePlaylistByUrl(
        'https://example.com/radio1.m3u',
      );
      expect(dup?.id, 'p1');

      // Reorder (move index 0 -> after index 1)
      await provider.reorderPlaylists(0, 2);
      expect(provider.playlists.map((p) => p.id), ['p2', 'p1']);

      // Category change
      await provider.setPlaylistCategory('p1', 'Favorit');
      expect(
        provider.playlists.firstWhere((p) => p.id == 'p1').category,
        'Favorit',
      );
    });
  });
}
