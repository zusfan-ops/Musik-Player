import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musik_m3u_player/providers/music_provider.dart';
import 'package:musik_m3u_player/services/github_m3u_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GithubM3uSyncService', () {
    test('parses valid m3u entries and formats display names', () {
      const payload = '''
      [
        {
          "name": "cctv_jakarta.m3u",
          "sha": "abc123",
          "type": "file",
          "download_url": "https://raw.githubusercontent.com/zusfan-ops/Musik-Player/main/m3u/cctv_jakarta.m3u"
        },
        {
          "name": "README.md",
          "sha": "def456",
          "type": "file",
          "download_url": "https://raw.githubusercontent.com/zusfan-ops/Musik-Player/main/m3u/README.md"
        }
      ]
      ''';

      final entries = GithubM3uSyncService.parseContentsResponse(payload);
      expect(entries, hasLength(1));
      expect(entries.first.name, 'cctv_jakarta.m3u');
      expect(
        GithubM3uSyncService.formatPlaylistDisplayName(entries.first.name),
        'CCTV Jakarta',
      );
      expect(
        GithubM3uSyncService.formatPlaylistDisplayName('cctv jepara.m3u'),
        'CCTV Jepara',
      );
    });

    test('throws FormatException when GitHub response is not a JSON list', () {
      expect(
        () => GithubM3uSyncService.parseContentsResponse('{"message":"error"}'),
        throwsFormatException,
      );
    });

    test('diffChangedEntries detects only new or updated SHAs', () {
      const remote = [
        GithubM3uFileEntry(
          name: 'cctv_jakarta.m3u',
          sha: 'sha1',
          downloadUrl: 'https://example.com/cctv_jakarta.m3u',
        ),
        GithubM3uFileEntry(
          name: 'cctv_semarang.m3u',
          sha: 'sha2-new',
          downloadUrl: 'https://example.com/cctv_semarang.m3u',
        ),
      ];

      final changed = GithubM3uSyncService.diffChangedEntries(
        remoteEntries: remote,
        knownShas: const {
          'cctv_jakarta.m3u': 'sha1',
          'cctv_semarang.m3u': 'sha2-old',
          'cctv jepara.m3u': 'sha-deleted',
        },
      );

      expect(changed.map((e) => e.name), ['cctv_semarang.m3u']);
    });
  });

  group('MusicProvider.syncGithubM3uDirectory deletion', () {
    test('removes deleted GitHub M3U playlist even with 0 additions/updates and persists removal', () async {
      const jeparaUrl =
          'https://raw.githubusercontent.com/zusfan-ops/Musik-Player/main/m3u/cctv%20jepara.m3u';
      const jakartaUrl =
          'https://raw.githubusercontent.com/zusfan-ops/Musik-Player/main/m3u/cctv_jakarta.m3u';
      const userCustomUrl = 'https://example.com/custom_jepara.m3u';

      SharedPreferences.setMockInitialValues({
        'github_m3u_shas_v1': jsonEncode({
          'cctv jepara.m3u': 'sha-jepara',
          'cctv_jakarta.m3u': 'sha-jakarta',
        }),
        'm3u_playlists_v1': <String>[
          jsonEncode({
            'id': 'pl-jepara',
            'name': 'CCTV Jepara',
            'sourceType': 'url',
            'sourceLocation': jeparaUrl,
            'tracks': [
              {
                'id': 't1',
                'title': 'Alun-alun Jepara',
                'artist': 'CCTV',
                'uri': 'https://stream.example.com/jepara.m3u8',
                'isVideo': true,
              }
            ],
            'updatedAt': '2026-11-28T00:00:00.000Z',
            'isEnabled': true,
          }),
          jsonEncode({
            'id': 'pl-jakarta',
            'name': 'CCTV Jakarta',
            'sourceType': 'url',
            'sourceLocation': jakartaUrl,
            'tracks': [],
            'updatedAt': '2026-11-28T00:00:00.000Z',
            'isEnabled': true,
          }),
          jsonEncode({
            'id': 'pl-user',
            'name': 'CCTV Jepara',
            'sourceType': 'url',
            'sourceLocation': userCustomUrl,
            'tracks': [],
            'updatedAt': '2026-11-28T00:00:00.000Z',
            'isEnabled': true,
          }),
        ],
      });

      final provider = MusicProvider(autoScanOnInit: false);
      await provider.initializeForTest();

      final client = MockClient((request) async {
        if (request.url.toString() == GithubM3uSyncService.apiContentsUrl) {
          return http.Response(
            jsonEncode([
              {
                'name': 'cctv_jakarta.m3u',
                'sha': 'sha-jakarta',
                'type': 'file',
                'download_url': jakartaUrl,
              },
            ]),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final count = await provider.syncGithubM3uDirectory(httpClient: client);
      expect(count, 1);
      expect(
        provider.playlists.any((p) => p.id == 'pl-jepara'),
        isFalse,
      );
      expect(
        provider.playlists.any((p) => p.id == 'pl-jakarta'),
        isTrue,
      );
      // User's non-GitHub playlist with same display name must NOT be deleted
      expect(
        provider.playlists.any((p) => p.id == 'pl-user'),
        isTrue,
      );
      expect(provider.pendingGithubM3uNotice, contains('1 dihapus (CCTV Jepara)'));

      // Verify persistence in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final savedShas = jsonDecode(prefs.getString('github_m3u_shas_v1')!) as Map;
      expect(savedShas.containsKey('cctv jepara.m3u'), isFalse);
      final savedPlaylists = prefs.getStringList('m3u_playlists_v1')!;
      expect(
        savedPlaylists
            .map((raw) => (jsonDecode(raw) as Map)['id'])
            .contains('pl-jepara'),
        isFalse,
      );
    });

    test('keeps playlists intact when GitHub API returns an error', () async {
      const jeparaUrl =
          'https://raw.githubusercontent.com/zusfan-ops/Musik-Player/main/m3u/cctv%20jepara.m3u';
      SharedPreferences.setMockInitialValues({
        'github_m3u_shas_v1': jsonEncode({'cctv jepara.m3u': 'sha-jepara'}),
        'm3u_playlists_v1': <String>[
          jsonEncode({
            'id': 'pl-jepara',
            'name': 'CCTV Jepara',
            'sourceType': 'url',
            'sourceLocation': jeparaUrl,
            'tracks': [],
            'updatedAt': '2026-11-28T00:00:00.000Z',
            'isEnabled': true,
          }),
        ],
      });

      final provider = MusicProvider(autoScanOnInit: false);
      await provider.initializeForTest();

      final failingClient = MockClient((_) async => http.Response('rate limit', 403));
      final count = await provider.syncGithubM3uDirectory(httpClient: failingClient);

      expect(count, 0);
      expect(provider.playlists.any((p) => p.id == 'pl-jepara'), isTrue);
    });
  });
}
