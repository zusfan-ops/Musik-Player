<?php

return [
    'paths' => ['api/*'],
    'allowed_methods' => ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    'allowed_origins' => config('mediacenter.cors_allowed_origins', ['https://mediacenter.ordr.my.id']),
    'allowed_origins_patterns' => [],
    'allowed_headers' => ['Content-Type', 'Authorization', 'Accept', 'If-None-Match'],
    'exposed_headers' => ['ETag'],
    'max_age' => 3600,
    'supports_credentials' => false,
];
