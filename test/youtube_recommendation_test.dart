import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:musik_m3u_player/services/newtube_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YouTubeRecommendationPrefs', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('falls back to default query when no history exists', () async {
      final q = await YouTubeRecommendationPrefs.getInitialQuery();
      expect(q, YouTubeRecommendationPrefs.defaultFallbackQuery);
    });

    test('prioritizes most searched and most played topics', () async {
      await YouTubeRecommendationPrefs.recordSearch('Sheila On 7');
      await YouTubeRecommendationPrefs.recordSearch('Dewa 19');
      await YouTubeRecommendationPrefs.recordSearch('Dewa 19');

      final initialAfterSearch =
          await YouTubeRecommendationPrefs.getInitialQuery();
      expect(initialAfterSearch, 'Dewa 19');

      await YouTubeRecommendationPrefs.recordPlay(
        const NewTubeItem(
          videoId: 'abc123',
          title: 'Separuh Aku',
          author: 'NOAH',
          thumbnailUrl: '',
        ),
      );
      await YouTubeRecommendationPrefs.recordPlay(
        const NewTubeItem(
          videoId: 'def456',
          title: 'Wanitaku',
          author: 'NOAH',
          thumbnailUrl: '',
        ),
      );

      final initialAfterPlay =
          await YouTubeRecommendationPrefs.getInitialQuery();
      expect(initialAfterPlay, 'NOAH');

      final quick = await YouTubeRecommendationPrefs.getQuickQueries();
      expect(quick.first, 'NOAH');
      expect(quick[1], 'Dewa 19');
      expect(quick.contains('Sheila On 7'), isTrue);
    });
  });
}
