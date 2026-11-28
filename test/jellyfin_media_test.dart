import 'package:flutter_test/flutter_test.dart';
import 'package:musik_m3u_player/models/jellyfin_profile_models.dart';
import 'package:musik_m3u_player/services/github_m3u_sync_service.dart';
import 'package:musik_m3u_player/services/jellyfin_service.dart';
import 'package:musik_m3u_player/services/update_checker_service.dart';

void main() {
  test('Parses Jellyfin Audio and Live TV channel entries', () {
    final audio = JellyfinMediaEntry.fromApiJson({
      'Id': 'a1',
      'Name': 'Lagu Satu',
      'Type': 'Audio',
      'Artists': ['Band A', 'Band B'],
      'Album': 'Album X',
      'RunTimeTicks': 1800000000,
      'ImageTags': {'Primary': 'tag'},
      'MediaSources': [
        {'Id': 'ms1'},
      ],
    });
    expect(audio.artist, 'Band A, Band B');
    expect(audio.album, 'Album X');
    expect(audio.durationSeconds, 180);
    expect(audio.mediaSourceId, 'ms1');
    expect(audio.hasPrimaryImage, isTrue);

    final tv = JellyfinMediaEntry.fromApiJson({
      'Id': 'c1',
      'Name': 'Channel 1',
      'Type': 'TvChannel',
      'Number': '12',
      'CurrentProgram': {'Name': 'Berita Pagi'},
    });
    expect(tv.channelNumber, '12');
    expect(tv.currentProgram, 'Berita Pagi');
    expect(tv.hasPrimaryImage, isFalse);
  });

  test('Builds Jellyfin audio stream URL without leaking API key', () {
    final uri = JellyfinService.buildAudioStreamUri(
      serverUrl: 'https://jf.example.com',
      itemId: 'a1',
      mediaSourceId: 'ms1',
    );
    expect(uri.path, '/Audio/a1/stream');
    expect(uri.queryParameters['static'], 'true');
    expect(uri.queryParameters['MediaSourceId'], 'ms1');
    expect(uri.toString().toLowerCase().contains('api_key'), isFalse);
  });

  test('Parses GitHub M3U contents API and detects new or updated SHAs', () {
    const jsonBody = '''
    [
      {
        "name": "CCTV Bima.m3u",
        "sha": "sha111",
        "type": "file",
        "download_url": "https://raw.githubusercontent.com/zusfan-ops/Musik-Player/main/m3u/CCTV%20Bima.m3u"
      },
      {
        "name": "CCTV Surabaya.m3u",
        "sha": "sha222",
        "type": "file",
        "download_url": "https://raw.githubusercontent.com/zusfan-ops/Musik-Player/main/m3u/CCTV%20Surabaya.m3u"
      },
      {
        "name": "README.md",
        "sha": "sha333",
        "type": "file",
        "download_url": "https://raw.githubusercontent.com/zusfan-ops/Musik-Player/main/m3u/README.md"
      }
    ]
    ''';

    final entries = GithubM3uSyncService.parseContentsResponse(jsonBody);
    expect(entries.length, 2);
    expect(entries.map((e) => e.name), ['CCTV Bima.m3u', 'CCTV Surabaya.m3u']);

    final changed = GithubM3uSyncService.diffChangedEntries(
      remoteEntries: entries,
      knownShas: const {'CCTV Bima.m3u': 'sha111'},
    );
    expect(changed.length, 1);
    expect(changed.first.name, 'CCTV Surabaya.m3u');
    expect(
      GithubM3uSyncService.formatPlaylistDisplayName('CCTV surabaya.m3u'),
      'CCTV Surabaya',
    );
  });

  test('UpdateCheckerService picks TV APK for Android TV and mobile APK for phones', () {
    final assets = [
      {
        'name': 'M3UMusik-v1.11.1-arm64-v8a.apk',
        'browser_download_url':
            'https://github.com/zusfan-ops/Musik-Player/releases/download/v1.11.1/M3UMusik-v1.11.1-arm64-v8a.apk',
      },
      {
        'name': 'MediaCenter-TV-v1.11.1-arm64-v8a.apk',
        'browser_download_url':
            'https://github.com/zusfan-ops/Musik-Player/releases/download/v1.11.1/MediaCenter-TV-v1.11.1-arm64-v8a.apk',
      },
    ];

    final tvAsset = UpdateCheckerService.selectBestApkAsset(
      assets,
      const ['arm64-v8a'],
      isTv: true,
    );
    expect(tvAsset?['name'], 'MediaCenter-TV-v1.11.1-arm64-v8a.apk');

    final phoneAsset = UpdateCheckerService.selectBestApkAsset(
      assets,
      const ['arm64-v8a'],
      isTv: false,
    );
    expect(phoneAsset?['name'], 'M3UMusik-v1.11.1-arm64-v8a.apk');
  });
}
