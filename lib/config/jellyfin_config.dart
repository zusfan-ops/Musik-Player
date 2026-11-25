/// Built-in integrated Jellyfin server configuration requested by the user.
class JellyfinBuiltInConfig {
  static const String serverUrl = String.fromEnvironment(
    'JELLYFIN_SERVER_URL',
    defaultValue: 'https://film.hallosemarang.com',
  );

  static const String apiKey = String.fromEnvironment(
    'JELLYFIN_API_KEY',
    defaultValue: '84984496841f4b2f942ce87f7a8e9c5f',
  );

  static const String username = String.fromEnvironment(
    'JELLYFIN_USER_NAME',
    defaultValue: 'nonton',
  );

  static const String defaultUserId = String.fromEnvironment(
    'JELLYFIN_USER_ID',
    defaultValue: 'cebe0f7a74b54354846fa7befbc474fe',
  );

  static const String defaultServerName = 'HallSem Media Center';
}
