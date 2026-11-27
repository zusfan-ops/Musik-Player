import 'package:flutter_test/flutter_test.dart';
import 'package:musik_m3u_player/models/jellyfin_profile_models.dart';
import 'package:musik_m3u_player/services/jellyfin_service.dart';

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
}
