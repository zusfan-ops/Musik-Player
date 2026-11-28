<?php

namespace App\Http\Controllers;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\View\View;

class LandingController extends Controller
{
    public const GITHUB_RELEASES_API = 'https://api.github.com/repos/zusfan-ops/Musik-Player/releases/latest';
    public const GITHUB_RELEASES_URL = 'https://github.com/zusfan-ops/Musik-Player/releases';

    public function index(): View
    {
        $release = $this->resolveLatestRelease();

        return view('landing', [
            'release' => $release,
            'githubReleasesUrl' => self::GITHUB_RELEASES_URL,
        ]);
    }

    /**
     * Fetch the latest release metadata from GitHub Releases with a 15-minute cache
     * and safe fallback to the latest verified release bundle.
     *
     * @return array<string, mixed>
     */
    private function resolveLatestRelease(): array
    {
        $cached = Cache::get('landing_github_latest_release');
        if (is_array($cached) && !empty($cached['groups'])) {
            return $cached;
        }

        try {
            $response = Http::timeout(4)
                ->withHeaders([
                    'User-Agent' => 'MediaCenter-Landing/1.0',
                    'Accept' => 'application/vnd.github+json',
                ])
                ->get(self::GITHUB_RELEASES_API);

            if ($response->successful()) {
                $payload = $response->json();
                if (is_array($payload) && !empty($payload['assets']) && is_array($payload['assets'])) {
                    $parsed = $this->formatReleasePayload($payload);
                    Cache::put('landing_github_latest_release', $parsed, now()->addMinutes(15));

                    return $parsed;
                }
            }
        } catch (\Throwable) {
            // Fall back gracefully when offline or rate-limited.
        }

        $fallback = $this->fallbackRelease();
        Cache::put('landing_github_latest_release', $fallback, now()->addMinutes(2));

        return $fallback;
    }

    /**
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    private function formatReleasePayload(array $payload): array
    {
        $rawTag = trim((string) ($payload['tag_name'] ?? ''));
        $tag = $rawTag !== '' ? $rawTag : 'v1.12.1';
        $version = ltrim($tag, 'v');
        $htmlUrl = $this->sanitizeHttpsUrl((string) ($payload['html_url'] ?? '')) ?? self::GITHUB_RELEASES_URL;
        $publishedAt = (string) ($payload['published_at'] ?? '');

        $windows = [];
        $androidMobile = [];
        $androidTv = [];

        foreach ($payload['assets'] as $asset) {
            if (!is_array($asset)) {
                continue;
            }

            $name = trim((string) ($asset['name'] ?? ''));
            $url = $this->sanitizeHttpsUrl((string) ($asset['browser_download_url'] ?? ''));
            $sizeBytes = (int) ($asset['size'] ?? 0);

            if ($name === '' || $url === null) {
                continue;
            }

            $item = [
                'name' => $name,
                'url' => $url,
                'size' => $this->formatBytes($sizeBytes),
                'arch' => $this->detectArch($name),
                'recommended' => $this->isRecommendedAsset($name),
                'badge' => $this->assetBadge($name),
                'description' => $this->assetDescription($name),
            ];

            if (str_ends_with(strtolower($name), '.exe')) {
                $windows[] = $item;
            } elseif (str_starts_with($name, 'MediaCenter-TV-') && str_ends_with(strtolower($name), '.apk')) {
                $androidTv[] = $item;
            } elseif (str_ends_with(strtolower($name), '.apk')) {
                $androidMobile[] = $item;
            }
        }

        $fallback = $this->fallbackRelease();
        $rawName = trim((string) ($payload['name'] ?? ''));

        return [
            'tag' => $tag,
            'version' => $version,
            'name' => $rawName !== '' ? $rawName : "Media Center {$tag}",
            'html_url' => $htmlUrl,
            'published_date' => $publishedAt !== '' ? substr($publishedAt, 0, 10) : $fallback['published_date'],
            'groups' => [
                'windows' => $windows !== [] ? $windows : $fallback['groups']['windows'],
                'android_mobile' => $androidMobile !== [] ? $androidMobile : $fallback['groups']['android_mobile'],
                'android_tv' => $androidTv !== [] ? $androidTv : $fallback['groups']['android_tv'],
            ],
        ];
    }

    private function sanitizeHttpsUrl(string $url): ?string
    {
        $trimmed = trim($url);
        if ($trimmed === '' || filter_var($trimmed, FILTER_VALIDATE_URL) === false) {
            return null;
        }

        return strtolower((string) parse_url($trimmed, PHP_URL_SCHEME)) === 'https'
            ? $trimmed
            : null;
    }

    private function detectArch(string $name): string
    {
        return match (true) {
            str_contains($name, 'arm64-v8a') => 'ARM64-v8a (64-bit)',
            str_contains($name, 'armeabi-v7a') => 'ARMv7-a (32-bit)',
            str_contains($name, 'x86_64') => 'x86_64',
            str_contains($name, 'x64') => 'Windows 64-bit (x64)',
            default => 'Universal',
        };
    }

    private function isRecommendedAsset(string $name): bool
    {
        return str_ends_with(strtolower($name), '.exe')
            || str_contains($name, 'arm64-v8a');
    }

    private function assetBadge(string $name): string
    {
        if (str_ends_with(strtolower($name), '.exe')) {
            return 'Installer Resmi';
        }
        if (str_contains($name, 'arm64-v8a')) {
            return 'Direkomendasikan';
        }
        if (str_contains($name, 'armeabi-v7a')) {
            return 'Perangkat 32-bit / STB';
        }

        return 'Emulator / x86_64';
    }

    private function assetDescription(string $name): string
    {
        if (str_ends_with(strtolower($name), '.exe')) {
            return 'Wizard instalasi Windows 10 & 11 lengkap dengan auto-update.';
        }
        if (str_starts_with($name, 'MediaCenter-TV-')) {
            return match (true) {
                str_contains($name, 'arm64-v8a') => 'Untuk Google TV & Android TV 64-bit modern dengan UI 10-foot.',
                str_contains($name, 'armeabi-v7a') => 'Ideal untuk STB Android TV & Mi Box 32-bit.',
                default => 'Untuk emulator Android TV berbasis arsitektur x86_64.',
            };
        }

        return match (true) {
            str_contains($name, 'arm64-v8a') => 'Untuk mayoritas HP & tablet Android modern (Android 8+).',
            str_contains($name, 'armeabi-v7a') => 'Untuk HP/tablet Android 32-bit atau jika arm64 gagal terpasang.',
            default => 'Untuk emulator Android atau tablet berbasis Intel/AMD x86_64.',
        };
    }

    private function formatBytes(int $bytes): string
    {
        if ($bytes <= 0) {
            return '~25 MB';
        }

        return number_format($bytes / 1048576, 1) . ' MB';
    }

    /**
     * @return array<string, mixed>
     */
    private function fallbackRelease(): array
    {
        $tag = 'v1.12.1';
        $base = "https://github.com/zusfan-ops/Musik-Player/releases/download/{$tag}";

        return [
            'tag' => $tag,
            'version' => '1.12.1',
            'name' => 'Media Center v1.12.1',
            'html_url' => "https://github.com/zusfan-ops/Musik-Player/releases/tag/{$tag}",
            'published_date' => '2026-11-27',
            'groups' => [
                'windows' => [
                    [
                        'name' => 'MediaCenter-Setup-v1.12.1-x64.exe',
                        'url' => "{$base}/MediaCenter-Setup-v1.12.1-x64.exe",
                        'size' => '25.4 MB',
                        'arch' => 'Windows 64-bit (x64)',
                        'recommended' => true,
                        'badge' => 'Installer Resmi',
                        'description' => 'Wizard instalasi Windows 10 & 11 lengkap dengan auto-update.',
                    ],
                ],
                'android_mobile' => [
                    [
                        'name' => 'M3UMusik-v1.12.1-arm64-v8a.apk',
                        'url' => "{$base}/M3UMusik-v1.12.1-arm64-v8a.apk",
                        'size' => '37.8 MB',
                        'arch' => 'ARM64-v8a (64-bit)',
                        'recommended' => true,
                        'badge' => 'Direkomendasikan',
                        'description' => 'Untuk mayoritas HP & tablet Android modern (Android 8+).',
                    ],
                    [
                        'name' => 'M3UMusik-v1.12.1-armeabi-v7a.apk',
                        'url' => "{$base}/M3UMusik-v1.12.1-armeabi-v7a.apk",
                        'size' => '35.4 MB',
                        'arch' => 'ARMv7-a (32-bit)',
                        'recommended' => false,
                        'badge' => 'Perangkat 32-bit / STB',
                        'description' => 'Untuk HP/tablet Android 32-bit atau jika arm64 gagal terpasang.',
                    ],
                    [
                        'name' => 'M3UMusik-v1.12.1-x86_64.apk',
                        'url' => "{$base}/M3UMusik-v1.12.1-x86_64.apk",
                        'size' => '42.4 MB',
                        'arch' => 'x86_64',
                        'recommended' => false,
                        'badge' => 'Emulator / x86_64',
                        'description' => 'Untuk emulator Android atau tablet berbasis Intel/AMD x86_64.',
                    ],
                ],
                'android_tv' => [
                    [
                        'name' => 'MediaCenter-TV-v1.12.1-arm64-v8a.apk',
                        'url' => "{$base}/MediaCenter-TV-v1.12.1-arm64-v8a.apk",
                        'size' => '35.8 MB',
                        'arch' => 'ARM64-v8a (64-bit)',
                        'recommended' => true,
                        'badge' => 'Direkomendasikan',
                        'description' => 'Untuk Google TV & Android TV 64-bit modern dengan UI 10-foot.',
                    ],
                    [
                        'name' => 'MediaCenter-TV-v1.12.1-armeabi-v7a.apk',
                        'url' => "{$base}/MediaCenter-TV-v1.12.1-armeabi-v7a.apk",
                        'size' => '33.2 MB',
                        'arch' => 'ARMv7-a (32-bit)',
                        'recommended' => false,
                        'badge' => 'Perangkat 32-bit / STB',
                        'description' => 'Ideal untuk STB Android TV & Mi Box 32-bit.',
                    ],
                    [
                        'name' => 'MediaCenter-TV-v1.12.1-x86_64.apk',
                        'url' => "{$base}/MediaCenter-TV-v1.12.1-x86_64.apk",
                        'size' => '40.4 MB',
                        'arch' => 'x86_64',
                        'recommended' => false,
                        'badge' => 'Emulator / x86_64',
                        'description' => 'Untuk emulator Android TV berbasis arsitektur x86_64.',
                    ],
                ],
            ],
        ];
    }
}
