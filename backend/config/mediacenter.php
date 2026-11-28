<?php

return [
    'api_base_url' => env('MEDIACENTER_API_BASE_URL', 'https://mediacenter.ordr.my.id/api/v1'),
    'max_devices_per_user' => (int) env('MEDIACENTER_MAX_DEVICES', 5),
    'max_playlists_per_user' => (int) env('MEDIACENTER_MAX_PLAYLISTS', 100),
    'max_items_per_playlist' => (int) env('MEDIACENTER_MAX_PLAYLIST_ITEMS', 500),
    'max_favorites_per_user' => (int) env('MEDIACENTER_MAX_FAVORITES', 1000),
    'analytics_retention_days' => (int) env('MEDIACENTER_ANALYTICS_RETENTION_DAYS', 90),
    'analytics_max_batch_size' => (int) env('MEDIACENTER_ANALYTICS_MAX_BATCH', 50),
    'cors_allowed_origins' => array_filter(array_map(
        'trim',
        explode(',', (string) env('MEDIACENTER_CORS_ORIGINS', 'https://mediacenter.ordr.my.id'))
    )),

    'allowed_analytics_events' => [
        'app_open',
        'app_session_started',
        'app_session_ended',
        'playlist_imported',
        'playlist_play_started',
        'audio_play_started',
        'video_play_started',
        'playback_error',
        'offline_mode_used',
        'app_update_available',
        'app_update_download_started',
        'app_feature_used',
        'network_error',
        'crash_report_automatic',
    ],

    'forbidden_analytics_attributes' => [
        'playlist_url',
        'stream_url',
        'file_path',
        'directory_path',
        'filename',
        'track_title',
        'artist_name',
        'device_ip_as_user_identifier',
        'auth_token',
        'account_id_as_raw_identifier',
        'precise_location',
        'password',
        'email',
    ],

    'privacy_summary' => 'MediaCenter dapat digunakan 100% offline tanpa akun. Path file lokal dan isi media pribadi tidak pernah dikirim ke server. Analitik bersifat opt-in, menggunakan ID instalasi acak pseudonim yang dapat direset atau dihapus kapan saja.',
];
