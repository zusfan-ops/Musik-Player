import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musik_m3u_player/main.dart';
import 'package:musik_m3u_player/models/music_models.dart';
import 'package:musik_m3u_player/services/directory_scanner_service.dart';
import 'package:musik_m3u_player/services/jellyfin_service.dart';
import 'package:musik_m3u_player/services/lyrics_service.dart';
import 'package:musik_m3u_player/services/m3u_service.dart';
import 'package:musik_m3u_player/services/newtube_service.dart';
import 'package:musik_m3u_player/services/update_checker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('M3uService, DirectoryScanner & JellyfinService Unit Tests', () {
    test('Parses Extended M3U with local relative/absolute paths and HTTP URLs', () {
      const sampleM3u = '''
#EXTM3U
#PLAYLIST:Koleksi Hits Offline & Stream
#EXTINF:245 group-title="Pop Indonesia" tvg-logo="https://img.example.com/1.jpg",Tulus - Hati-Hati di Jalan
subfolder/hati_hati_di_jalan.mp3
#EXTINF:198 group-title="Rock",Dewa 19 - Kangen
/storage/emulated/0/Music/Rock/dewa19_kangen.flac
#EXTINF:-1 group-title="Radio Live",Prambors FM - Live Stream
https://stream.example.com/live.mp3
''';

      final result = M3uService.parseM3uContent(
        content: sampleM3u,
        playlistId: 'pl_test_1',
        fallbackPlaylistName: 'Fallback Name',
        baseDirectoryPath: '/storage/emulated/0/Playlists',
      );

      expect(result.embeddedTitle, 'Koleksi Hits Offline & Stream');
      expect(result.tracks.length, 3);
      expect(result.tracks[0].artist, 'Tulus');
      expect(result.tracks[0].isOfflineReady, isTrue);
      expect(result.tracks[0].isVideo, isFalse);
      expect(result.tracks[2].sourceType, TrackSourceType.remoteStream);
      expect(result.tracks[2].isOfflineReady, isFalse);
    });

    test('Detects IPTV / Video M3U streams, parses #EXTVLCOPT headers, and cleans Undefined groups', () {
      const iptvM3u = '''
#EXTM3U
#EXTINF:-1 tvg-id="tvone.id" tvg-logo="https://img.example.com/tvone.png" group-title="Undefined",tvOne HD (720p)
#EXTVLCOPT:http-user-agent=VLC/3.0.20
#EXTVLCOPT:http-referrer=https://tvone.example.com/
https://live.example.com/tvone/index.m3u8
''';

      final parsed = M3uService.parseM3uContent(
        content: iptvM3u,
        playlistId: 'pl_iptv',
        fallbackPlaylistName: 'TV Nasional',
      );

      expect(parsed.tracks.length, 1);
      final ch = parsed.tracks.first;
      expect(ch.title, 'tvOne HD (720p)');
      expect(ch.isVideo, isTrue);
      expect(ch.groupTitle, isNull);
      expect(ch.directoryName, 'TV Nasional');
      expect(ch.httpHeaders?['User-Agent'], 'VLC/3.0.20');
      expect(ch.httpHeaders?['Referer'], 'https://tvone.example.com/');
    });

    test('Generates short deterministic filename stems (< 48 chars) preventing ENAMETOOLONG', () {
      final veryLongUrl =
          'https://cdn.example.com/music/${'a' * 400}/track_with_very_long_query.mp3?token=${'x' * 200}';
      final id = TrackItem.generateId(veryLongUrl, playlistId: 'playlist_long');
      final stem = M3uService.safeCacheFileStem(veryLongUrl, prefix: 'aud');

      expect(id.length, lessThan(48));
      expect(stem.length, lessThan(48));
    });

    test('Resolves Android SAF content:// tree and document URIs accurately', () {
      final docUri = Uri.parse(
        'content://com.android.externalstorage.documents/document/primary%3AMusic%2FIndo%2Fhits.m3u8',
      );
      final treeUri = Uri.parse(
        'content://com.android.externalstorage.documents/tree/primary%3AMusic%2FRock',
      );
      expect(
        DirectoryScannerService.resolveAndroidSafUriToPath(docUri),
        '/storage/emulated/0/Music/Indo/hits.m3u8',
      );
      expect(
        DirectoryScannerService.resolveAndroidSafUriToPath(treeUri),
        '/storage/emulated/0/Music/Rock',
      );
    });

    test('Filters out system Ringtones/Notifications/Alarms unless user explicitly adds them', () {
      expect(
        DirectoryScannerService.isSystemTonePath(
          '/storage/emulated/0/Ringtones/bell.mp3',
          const {},
        ),
        isTrue,
      );
      expect(
        DirectoryScannerService.isSystemTonePath(
          '/storage/emulated/0/Music/Pop/lagu.mp3',
          const {},
        ),
        isFalse,
      );
      expect(
        DirectoryScannerService.isSystemTonePath(
          '/storage/emulated/0/Ringtones/bell.mp3',
          const {'/storage/emulated/0/Ringtones'},
        ),
        isFalse,
      );
    });

    test('Compares semantic versions and selects matching ABI APK from GitHub Release assets', () {
      expect(UpdateCheckerService.isNewerVersion('v1.4.0', '1.3.0'), isTrue);
      expect(UpdateCheckerService.isNewerVersion('1.3.1', '1.3.0'), isTrue);
      expect(UpdateCheckerService.isNewerVersion('1.3.0', '1.3.0'), isFalse);
      expect(UpdateCheckerService.isNewerVersion('1.2.9', '1.3.0'), isFalse);

      final assets = [
        {
          'name': 'M3UMusik-v1.4.0-armeabi-v7a.apk',
          'browser_download_url':
              'https://github.com/zusfan-ops/Musik-Player/releases/download/v1.4.0/M3UMusik-v1.4.0-armeabi-v7a.apk',
          'size': 18500000,
        },
        {
          'name': 'M3UMusik-v1.4.0-arm64-v8a.apk',
          'browser_download_url':
              'https://github.com/zusfan-ops/Musik-Player/releases/download/v1.4.0/M3UMusik-v1.4.0-arm64-v8a.apk',
          'size': 21000000,
        },
      ];
      final picked =
          UpdateCheckerService.selectBestApkAsset(assets, const ['arm64-v8a']);
      expect(picked?['name'], 'M3UMusik-v1.4.0-arm64-v8a.apk');
    });

    test('Normalizes Jellyfin URLs, validates API keys, builds clean stream URIs, and scrubs secrets', () {
      expect(
        JellyfinService.normalizeServerUrl('192.168.1.50:8096///'),
        'http://192.168.1.50:8096',
      );
      expect(
        JellyfinService.validateApiKey('  abcdef1234567890  '),
        'abcdef1234567890',
      );
      expect(
        () => JellyfinService.validateApiKey('short'),
        throwsFormatException,
      );

      final directUri = JellyfinService.buildDirectStreamUri(
        serverUrl: 'https://jf.example.com',
        itemId: 'movie123',
        mediaSourceId: 'ms456',
      );
      expect(directUri.toString(), contains('/Videos/movie123/stream'));
      expect(directUri.toString(), isNot(contains('api_key')));

      final hlsUri = JellyfinService.buildHlsStreamUri(
        serverUrl: 'https://jf.example.com',
        itemId: 'movie123',
        mediaSourceId: null,
        playSessionId: 'ps_1',
      );
      expect(hlsUri.queryParameters['MediaSourceId'], 'movie123');
      expect(hlsUri.queryParameters['DeviceId'], JellyfinService.defaultDeviceId);
      expect(hlsUri.queryParameters['SegmentContainer'], 'ts');

      final headers = JellyfinService.buildAuthHeaders('testkey123456');
      expect(headers['Authorization'], startsWith('MediaBrowser '));
      expect(headers['Authorization'], contains('Token="testkey123456"'));

      final scrubbed = JellyfinService.sanitizeErrorMessage(
        'Failed with key secretToken999 and api_key=secretToken999',
        'secretToken999',
      );
      expect(scrubbed, isNot(contains('secretToken999')));
    });

    test('Parses LRC timestamps and resolves active lyric line accurately', () {
      const sampleLrc = '''
[00:12.50]Baris pertama lagu
[00:25.00][01:10.00]Reffrain yang sama
[00:40.250]Baris ketiga
''';
      final lines = LyricsService.parseLrc(sampleLrc);
      expect(lines.length, 4);
      expect(lines.first.text, 'Baris pertama lagu');
      expect(lines.last.timestamp, const Duration(minutes: 1, seconds: 10));

      expect(LyricsService.activeLineIndex(lines, const Duration(seconds: 5)), -1);
      expect(LyricsService.activeLineIndex(lines, const Duration(seconds: 15)), 0);
      expect(LyricsService.activeLineIndex(lines, const Duration(seconds: 42)), 2);
      expect(
        LyricsService.activeLineIndex(lines, const Duration(minutes: 1, seconds: 12)),
        3,
      );
    });

    test('Extracts YouTube video IDs from watch, share, and shorts URLs', () {
      expect(
        NewTubeService.extractVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(
        NewTubeService.extractVideoId('https://youtu.be/wAPCSnAhhC8?si=abc'),
        'wAPCSnAhhC8',
      );
      expect(
        NewTubeService.extractVideoId('https://youtube.com/shorts/jfKfPfyJRdk'),
        'jfKfPfyJRdk',
      );
      expect(NewTubeService.extractVideoId('lofi hip hop'), isNull);
    });

    test('Sanitizes YouTube playlist and track filenames safely', () {
      expect(
        NewTubeService.sanitizeFileName('Metallica: Best Of / Live? *2025*'),
        'Metallica Best Of Live 2025',
      );
      expect(
        NewTubeService.sanitizeFileName('   <<<>>>   ', fallback: 'Offline'),
        'Offline',
      );
    });

    test('Extracts YouTube playlist IDs from playlist and watch URLs', () {
      expect(
        NewTubeService.extractPlaylistId(
          'https://www.youtube.com/playlist?list=PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG',
        ),
        'PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG',
      );
      expect(
        NewTubeService.extractPlaylistId(
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=RDdQw4w9WgXcQ',
        ),
        'RDdQw4w9WgXcQ',
      );
      expect(NewTubeService.extractPlaylistId('metallica hits'), isNull);
    });
  });

  testWidgets(
      'MusikM3uApp renders logo2 splash, navigates to Film Jellyfin and Profil & Setting',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MusikM3uApp(autoScanOnInit: false));

    // Initial splash screen with MEDIACENTER branding
    expect(find.text('MEDIACENTER'), findsOneWidget);

    // Advance past splash gate timer and settle provider initialization
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(seconds: 3));

    // Main 5-tab Netflix x Spotify shell should be visible
    expect(find.text('MediaCenter'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('modern_bottom_nav')),
        matching: find.text('YouTube'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('modern_bottom_nav')),
        matching: find.text('Lainnya'),
      ),
      findsOneWidget,
    );

    // Open Hallsem Cinema tab via Lainnya (More) menu
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('modern_bottom_nav')),
        matching: find.text('Lainnya'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hallsem Cinema (Film)'));
    await tester.pumpAndSettle();
    expect(find.text('Hallsem Cinema'), findsWidgets);
    expect(find.text('Input API Code Jellyfin di Setting'), findsNothing);

    // Open Profil & Setting tab via Lainnya (More) menu
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('modern_bottom_nav')),
        matching: find.text('Lainnya'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profil & Setting'));
    await tester.pumpAndSettle();
    await tester.pump();
    expect(find.text('Profil & Setting'), findsOneWidget);
    expect(find.text('Pilih Karakter Avatar Preset'), findsOneWidget);

    // Scroll down inside ProfileSettingsScreen ListView to verify Hallsem Cinema & Developer Info
    await tester.scrollUntilVisible(
      find.text('Hallsem Cinema Terintegrasi'),
      250,
      scrollable: find.descendant(
        of: find.byType(Scaffold).last,
        matching: find.byType(Scrollable).first,
      ),
    );
    expect(find.text('Hallsem Cinema Terintegrasi'), findsOneWidget);
    expect(find.text('Simpan & Hubungkan Jellyfin'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Zusfan Mashuri'),
      250,
      scrollable: find.descendant(
        of: find.byType(Scaffold).last,
        matching: find.byType(Scrollable).first,
      ),
    );
    expect(find.text('Zusfan Mashuri'), findsOneWidget);
    expect(find.text('https://zusfan.hallosemarang.com'), findsOneWidget);

    // Open Panduan Penggunaan Aplikasi (OnboardingScreen)
    await tester.scrollUntilVisible(
      find.text('Panduan Penggunaan Aplikasi'),
      -250,
      scrollable: find.descendant(
        of: find.byType(Scaffold).last,
        matching: find.byType(Scrollable).first,
      ),
    );
    expect(find.text('Panduan Penggunaan Aplikasi'), findsOneWidget);
    await tester.tap(find.text('Panduan Penggunaan Aplikasi'));
    await tester.pumpAndSettle();
    expect(find.text('Putar Musik dari Folder HP'), findsOneWidget);
    await tester.tap(find.text('Lewati'));
    await tester.pumpAndSettle();
    expect(find.text('Putar Musik dari Folder HP'), findsNothing);
  });
}
