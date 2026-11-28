<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class ExampleTest extends TestCase
{
    public function test_landing_page_renders_github_release_links(): void
    {
        Cache::forget('landing_github_latest_release');

        Http::fake([
            'api.github.com/*' => Http::response([
                'tag_name' => 'v1.13.0',
                'name' => 'Media Center v1.13.0',
                'html_url' => 'https://github.com/zusfan-ops/Musik-Player/releases/tag/v1.13.0',
                'published_at' => '2026-11-28T10:00:00Z',
                'assets' => [
                    [
                        'name' => 'MediaCenter-Setup-v1.13.0-x64.exe',
                        'browser_download_url' => 'https://github.com/zusfan-ops/Musik-Player/releases/download/v1.13.0/MediaCenter-Setup-v1.13.0-x64.exe',
                        'size' => 26663121,
                    ],
                    [
                        'name' => 'M3UMusik-v1.13.0-arm64-v8a.apk',
                        'browser_download_url' => 'https://github.com/zusfan-ops/Musik-Player/releases/download/v1.13.0/M3UMusik-v1.13.0-arm64-v8a.apk',
                        'size' => 39676411,
                    ],
                    [
                        'name' => 'MediaCenter-TV-v1.13.0-arm64-v8a.apk',
                        'browser_download_url' => 'https://github.com/zusfan-ops/Musik-Player/releases/download/v1.13.0/MediaCenter-TV-v1.13.0-arm64-v8a.apk',
                        'size' => 37579259,
                    ],
                ],
            ], 200),
        ]);

        $response = $this->get('/');

        $response->assertStatus(200);
        $response->assertSee('MediaCenter');
        $response->assertSee('v1.13.0');
        $response->assertSee('https://github.com/zusfan-ops/Musik-Player/releases/download/v1.13.0/MediaCenter-Setup-v1.13.0-x64.exe');
        $response->assertSee('https://github.com/zusfan-ops/Musik-Player/releases/download/v1.13.0/M3UMusik-v1.13.0-arm64-v8a.apk');
        $response->assertSee('https://github.com/zusfan-ops/Musik-Player/releases/download/v1.13.0/MediaCenter-TV-v1.13.0-arm64-v8a.apk');
    }

    public function test_landing_page_falls_back_gracefully_when_github_fails(): void
    {
        Cache::forget('landing_github_latest_release');

        Http::fake([
            'api.github.com/*' => Http::response([], 503),
        ]);

        $response = $this->get('/');

        $response->assertStatus(200);
        $response->assertSee('v1.12.1');
        $response->assertSee('https://github.com/zusfan-ops/Musik-Player/releases/download/v1.12.1/MediaCenter-Setup-v1.12.1-x64.exe');
    }
}
