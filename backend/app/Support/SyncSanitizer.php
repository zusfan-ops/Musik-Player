<?php

namespace App\Support;

use Illuminate\Validation\ValidationException;

class SyncSanitizer
{
    /**
     * Rejects local filesystem paths (Windows drive, Unix root, content://, file://).
     */
    public static function assertNoLocalPath(?string $value, string $field): void
    {
        if ($value === null || $value === '') {
            return;
        }
        $trimmed = trim($value);
        if (
            preg_match('/^[a-zA-Z]:[\\\\\\/]/', $trimmed) ||
            str_starts_with($trimmed, '/') ||
            str_starts_with($trimmed, '\\\\') ||
            preg_match('/^(file|content):\/\//i', $trimmed)
        ) {
            throw ValidationException::withMessages([
                $field => ['Path penyimpanan lokal perangkat tidak boleh dikirim ke server.'],
            ]);
        }
    }

    /**
     * Validates an optional remote stream/playlist URL (http/https/rtsp/rtmp/ws/wss only, blocks private/loopback).
     */
    public static function sanitizeRemoteUrl(?string $url, string $field): ?string
    {
        if ($url === null || trim($url) === '') {
            return null;
        }
        $trimmed = trim($url);
        self::assertNoLocalPath($trimmed, $field);

        $parts = parse_url($trimmed);
        $scheme = strtolower($parts['scheme'] ?? '');
        $host = strtolower($parts['host'] ?? '');
        if (!in_array($scheme, ['http', 'https', 'rtsp', 'rtmp', 'ws', 'wss'], true) || $host === '') {
            throw ValidationException::withMessages([
                $field => ['URL stream atau playlist tidak valid.'],
            ]);
        }
        if (in_array($host, ['localhost', '127.0.0.1', '::1', '0.0.0.0'], true)) {
            throw ValidationException::withMessages([
                $field => ['Host lokal tidak diizinkan untuk sinkronisasi.'],
            ]);
        }
        return $trimmed;
    }

    /**
     * Strips any forbidden or path-like keys from arbitrary JSON maps (settings/analytics).
     */
    public static function sanitizeExtraMap(?array $data, array $forbiddenKeys = []): array
    {
        if ($data === null) {
            return [];
        }
        $blocked = array_map('strtolower', $forbiddenKeys);
        $clean = [];
        foreach ($data as $key => $val) {
            $lowerKey = strtolower((string) $key);
            if (in_array($lowerKey, $blocked, true)) {
                continue;
            }
            if (str_contains($lowerKey, 'path') || str_contains($lowerKey, 'token') || str_contains($lowerKey, 'password')) {
                continue;
            }
            if (is_string($val)) {
                if (
                    preg_match('/^[a-zA-Z]:[\\\\\\/]/', $val) ||
                    preg_match('/^\/(storage|sdcard|Users|home|var|etc)\//i', $val)
                ) {
                    continue;
                }
                $clean[$key] = mb_substr($val, 0, 200);
            } elseif (is_scalar($val)) {
                $clean[$key] = $val;
            }
        }
        return $clean;
    }
}
