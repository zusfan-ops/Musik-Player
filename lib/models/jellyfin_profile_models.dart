import 'package:flutter/material.dart';

enum AvatarSourceMode {
  preset,
  customFile,
  jellyfinAvatar,
}

class AvatarPresetStyle {
  final int index;
  final String label;
  final IconData icon;
  final List<Color> gradientColors;

  const AvatarPresetStyle({
    required this.index,
    required this.label,
    required this.icon,
    required this.gradientColors,
  });

  static const List<AvatarPresetStyle> presets = [
    AvatarPresetStyle(
      index: 0,
      label: 'Vinyl Crimson',
      icon: Icons.album_rounded,
      gradientColors: [Color(0xFFE50914), Color(0xFF881337)],
    ),
    AvatarPresetStyle(
      index: 1,
      label: 'Spotify Emerald',
      icon: Icons.headphones_rounded,
      gradientColors: [Color(0xFF1DB954), Color(0xFF065F46)],
    ),
    AvatarPresetStyle(
      index: 2,
      label: 'Neon Cyber',
      icon: Icons.graphic_eq_rounded,
      gradientColors: [Color(0xFF00E5FF), Color(0xFF1D4ED8)],
    ),
    AvatarPresetStyle(
      index: 3,
      label: 'Cinema Director',
      icon: Icons.movie_filter_rounded,
      gradientColors: [Color(0xFFF59E0B), Color(0xFFB45309)],
    ),
    AvatarPresetStyle(
      index: 4,
      label: 'Cosmic Synth',
      icon: Icons.auto_awesome_rounded,
      gradientColors: [Color(0xFFA855F7), Color(0xFF4C1D95)],
    ),
    AvatarPresetStyle(
      index: 5,
      label: 'Acoustic Indie',
      icon: Icons.music_note_rounded,
      gradientColors: [Color(0xFFEC4899), Color(0xFF9D174D)],
    ),
    AvatarPresetStyle(
      index: 6,
      label: 'Midnight Studio',
      icon: Icons.speaker_rounded,
      gradientColors: [Color(0xFF38BDF8), Color(0xFF0F172A)],
    ),
    AvatarPresetStyle(
      index: 7,
      label: 'Popcorn Premiere',
      icon: Icons.theaters_rounded,
      gradientColors: [Color(0xFFEF4444), Color(0xFF7C2D12)],
    ),
  ];

  static AvatarPresetStyle byIndex(int idx) {
    if (idx < 0 || idx >= presets.length) return presets.first;
    return presets[idx];
  }
}

class JellyfinUserSummary {
  final String id;
  final String name;
  final bool hasPrimaryImage;

  const JellyfinUserSummary({
    required this.id,
    required this.name,
    this.hasPrimaryImage = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'hasPrimaryImage': hasPrimaryImage,
      };

  factory JellyfinUserSummary.fromJson(Map<String, dynamic> json) {
    return JellyfinUserSummary(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Jellyfin User',
      hasPrimaryImage: json['hasPrimaryImage'] as bool? ?? false,
    );
  }
}

/// Generic Jellyfin entry for Music tracks (`Audio`) and Live TV channels.
class JellyfinMediaEntry {
  final String id;
  final String name;
  final String itemType; // Audio | TvChannel
  final String? artist;
  final String? album;
  final String? channelNumber;
  final String? currentProgram;
  final int? runTimeTicks;
  final String? mediaSourceId;
  final bool hasPrimaryImage;

  const JellyfinMediaEntry({
    required this.id,
    required this.name,
    required this.itemType,
    this.artist,
    this.album,
    this.channelNumber,
    this.currentProgram,
    this.runTimeTicks,
    this.mediaSourceId,
    this.hasPrimaryImage = false,
  });

  int? get durationSeconds {
    if (runTimeTicks == null || runTimeTicks! <= 0) return null;
    return runTimeTicks! ~/ 10000000;
  }

  factory JellyfinMediaEntry.fromApiJson(Map<String, dynamic> json) {
    final imageTags = json['ImageTags'] as Map<String, dynamic>? ?? const {};
    final mediaSources = json['MediaSources'] as List<dynamic>? ?? const [];
    final artists = json['Artists'] as List<dynamic>? ?? const [];
    final program = json['CurrentProgram'] as Map<String, dynamic>?;

    String? sourceId;
    if (mediaSources.isNotEmpty && mediaSources.first is Map<String, dynamic>) {
      sourceId = (mediaSources.first as Map<String, dynamic>)['Id'] as String?;
    }

    return JellyfinMediaEntry(
      id: json['Id'] as String? ?? '',
      name: json['Name'] as String? ?? 'Tanpa Judul',
      itemType: json['Type'] as String? ?? 'Audio',
      artist: artists.whereType<String>().isNotEmpty
          ? artists.whereType<String>().join(', ')
          : json['AlbumArtist'] as String?,
      album: json['Album'] as String?,
      channelNumber: json['Number'] as String?,
      currentProgram: program?['Name'] as String?,
      runTimeTicks: (json['RunTimeTicks'] as num?)?.toInt(),
      mediaSourceId: sourceId,
      hasPrimaryImage: imageTags.containsKey('Primary'),
    );
  }
}

class JellyfinMovieItem {
  final String id;
  final String name;
  final String itemType; // Movie | Episode | Video
  final String? seriesName;
  final String? overview;
  final int? productionYear;
  final double? communityRating;
  final String? officialRating;
  final List<String> genres;
  final int? runTimeTicks;
  final String? mediaSourceId;
  final String? container;
  final bool hasPrimaryImage;
  final bool hasBackdropImage;
  final int playbackPositionTicks;

  const JellyfinMovieItem({
    required this.id,
    required this.name,
    required this.itemType,
    this.seriesName,
    this.overview,
    this.productionYear,
    this.communityRating,
    this.officialRating,
    this.genres = const [],
    this.runTimeTicks,
    this.mediaSourceId,
    this.container,
    this.hasPrimaryImage = false,
    this.hasBackdropImage = false,
    this.playbackPositionTicks = 0,
  });

  Duration? get duration {
    if (runTimeTicks == null || runTimeTicks! <= 0) return null;
    return Duration(milliseconds: runTimeTicks! ~/ 10000);
  }

  String get formattedDuration {
    final d = duration;
    if (d == null) return 'Film';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}j ${m}m';
    return '${m}m';
  }

  String get displaySubtitle {
    final parts = <String>[
      if (seriesName != null && seriesName!.isNotEmpty) seriesName!,
      if (productionYear != null) '$productionYear',
      formattedDuration,
      if (container != null && container!.isNotEmpty) container!.toUpperCase(),
    ];
    return parts.join(' • ');
  }

  double get serverResumeRatio {
    if (runTimeTicks == null ||
        runTimeTicks! <= 0 ||
        playbackPositionTicks <= 0) {
      return 0.0;
    }
    return (playbackPositionTicks / runTimeTicks!).clamp(0.0, 1.0);
  }

  factory JellyfinMovieItem.fromApiJson(Map<String, dynamic> json) {
    final imageTags = json['ImageTags'] as Map<String, dynamic>? ?? const {};
    final backdropTags =
        json['BackdropImageTags'] as List<dynamic>? ?? const [];
    final mediaSources = json['MediaSources'] as List<dynamic>? ?? const [];
    final userData = json['UserData'] as Map<String, dynamic>? ?? const {};

    String? firstMediaSourceId;
    String? firstContainer;
    if (mediaSources.isNotEmpty && mediaSources.first is Map<String, dynamic>) {
      final ms = mediaSources.first as Map<String, dynamic>;
      firstMediaSourceId = ms['Id'] as String?;
      firstContainer = ms['Container'] as String?;
    }

    final rawGenres = json['Genres'] as List<dynamic>? ?? const [];

    return JellyfinMovieItem(
      id: json['Id'] as String? ?? '',
      name: json['Name'] as String? ?? 'Untitled Video',
      itemType: json['Type'] as String? ?? 'Movie',
      seriesName: json['SeriesName'] as String?,
      overview: json['Overview'] as String?,
      productionYear: (json['ProductionYear'] as num?)?.toInt(),
      communityRating: (json['CommunityRating'] as num?)?.toDouble(),
      officialRating: json['OfficialRating'] as String?,
      genres: rawGenres.whereType<String>().toList(),
      runTimeTicks: (json['RunTimeTicks'] as num?)?.toInt(),
      mediaSourceId: firstMediaSourceId,
      container: firstContainer,
      hasPrimaryImage: imageTags.containsKey('Primary'),
      hasBackdropImage: backdropTags.isNotEmpty,
      playbackPositionTicks:
          (userData['PlaybackPositionTicks'] as num?)?.toInt() ?? 0,
    );
  }
}
