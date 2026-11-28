import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musik_m3u_player/models/music_models.dart';
import 'package:musik_m3u_player/providers/music_provider.dart';
import 'package:musik_m3u_player/services/newtube_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YouTube Audio Cache-First & Data Saver', () {
    test('ytAutoCacheEnabled defaults to true and persists toggle', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = MusicProvider(autoScanOnInit: false);
      await provider.initializeForTest();

      expect(provider.ytAutoCacheEnabled, isTrue);

      await provider.setYtAutoCacheEnabled(false);
      expect(provider.ytAutoCacheEnabled, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('yt_auto_cache_enabled_v1'), isFalse);
    });

    test('resolveNewTubeAudioTrack uses local cached file without network call', () async {
      SharedPreferences.setMockInitialValues({});
      final tempDir = await Directory.systemTemp.createTemp('yt_cache_test_');
      try {
        final provider = MusicProvider(autoScanOnInit: false)
          ..offlineRootOverride = tempDir;
        await provider.initializeForTest();

        final cacheDir = Directory(p.join(tempDir.path, '.stream_cache'));
        await cacheDir.create(recursive: true);

        final cachedFile = File(p.join(cacheDir.path, 'dQw4w9WgXcQ.m4a'));
        await cachedFile.writeAsBytes(List<int>.filled(4096, 7));

        const item = NewTubeItem(
          videoId: 'dQw4w9WgXcQ',
          title: 'Cached Song',
          author: 'Artist',
          thumbnailUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
          duration: Duration(minutes: 3),
        );

        final track = await provider.resolveNewTubeAudioTrack(item);
        expect(track, isNotNull);
        expect(track!.sourceType, TrackSourceType.localFile);
        expect(track.pathOrUrl, cachedFile.path);
        expect(track.localFileAvailable, isTrue);

        // Verify LRU eviction helper keeps newest files within targetBytes
        final oldFile = File(p.join(cacheDir.path, 'old123.m4a'));
        await oldFile.writeAsBytes(List<int>.filled(2048, 1));
        await oldFile.setLastModified(DateTime(2025, 1, 1));

        final newFile = File(p.join(cacheDir.path, 'new456.m4a'));
        await newFile.writeAsBytes(List<int>.filled(2048, 2));
        await newFile.setLastModified(DateTime(2026, 1, 1));

        await provider.enforceYouTubeStreamCacheLimit(
          cacheDir,
          maxBytes: 7000,
          targetBytes: 6200,
        );

        expect(await oldFile.exists(), isFalse);
        expect(await newFile.exists(), isTrue);

        // Verify invalid videoId is rejected safely by cache lookup
        final badLookup = await provider.findCachedYouTubeAudioFile('../evil');
        expect(badLookup, isNull);
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });
}
