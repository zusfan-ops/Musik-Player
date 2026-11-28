<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\AnnouncementResource;
use App\Http\Resources\AppReleaseResource;
use App\Models\Announcement;
use App\Models\AppRelease;
use App\Models\M3uSource;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpFoundation\StreamedResponse;
use Illuminate\Support\Facades\DB;

class PublicController extends Controller
{
    public function health(): JsonResponse
    {
        $dbOk = false;
        try {
            DB::connection()->getPdo();
            $dbOk = true;
        } catch (\Throwable) {
            $dbOk = false;
        }

        return response()->json([
            'status' => $dbOk ? 'ok' : 'degraded',
            'database' => $dbOk ? 'connected' : 'unavailable',
            'timestamp' => now()->toIso8601String(),
        ], $dbOk ? 200 : 503);
    }

    public function appConfig(): JsonResponse
    {
        return response()->json([
            'api_base_url' => config('mediacenter.api_base_url'),
            'guest_mode_enabled' => true,
            'sync_requires_opt_in' => true,
            'limits' => [
                'max_playlists_per_user' => config('mediacenter.max_playlists_per_user'),
                'max_items_per_playlist' => config('mediacenter.max_items_per_playlist'),
                'max_favorites_per_user' => config('mediacenter.max_favorites_per_user'),
                'analytics_max_batch_size' => config('mediacenter.analytics_max_batch_size'),
                'analytics_retention_days' => config('mediacenter.analytics_retention_days'),
            ],
            'allowed_analytics_events' => config('mediacenter.allowed_analytics_events'),
            'privacy_summary' => config('mediacenter.privacy_summary'),
        ]);
    }

    public function announcements(Request $request): JsonResponse
    {
        $items = Announcement::currentlyVisible()->get();
        $lastUpdated = $items->max('updated_at')?->toIso8601String() ?? 'empty';
        $etag = '"' . sha1($lastUpdated . ':' . $items->count()) . '"';

        if ($request->headers->get('If-None-Match') === $etag) {
            return response()->json(null, 304)->header('ETag', $etag);
        }

        return response()
            ->json([
                'data' => AnnouncementResource::collection($items),
                'etag' => $etag,
            ])
            ->header('ETag', $etag)
            ->header('Cache-Control', 'public, max-age=120');
    }

    public function latestRelease(Request $request): JsonResponse
    {
        $platform = strtolower((string) $request->query('platform', 'android'));
        $abi = strtolower((string) $request->query('abi', 'arm64-v8a'));

        if (!in_array($platform, ['android', 'android_tv', 'windows'], true)) {
            $platform = 'android';
        }

        $release = AppRelease::query()
            ->where('is_active', true)
            ->where('platform', $platform)
            ->where('abi', $abi)
            ->orderByDesc('build_number')
            ->first();

        if (!$release) {
            $release = AppRelease::query()
                ->where('is_active', true)
                ->where('platform', $platform)
                ->orderByDesc('build_number')
                ->first();
        }

        if (!$release) {
            return response()->json([
                'message' => 'Belum ada metadata rilis untuk platform ini.',
                'data' => null,
            ], 404);
        }

        return response()->json([
            'data' => new AppReleaseResource($release),
        ]);
    }

    public function m3uSources(): JsonResponse
    {
        $sources = M3uSource::query()
            ->where('is_active', true)
            ->orderByDesc('updated_at')
            ->get()
            ->map(function (M3uSource $src) {
                $downloadUrl = $src->source_type === 'file'
                    ? route('api.v1.m3u-sources.download', ['m3uSource' => $src->id])
                    : (string) $src->source_url;

                return [
                    'id' => $src->id,
                    'name' => $src->name,
                    'category' => $src->category,
                    'source_type' => $src->source_type,
                    'download_url' => $downloadUrl,
                    'sha256' => $src->content_sha256,
                    'updated_at' => $src->updated_at?->toIso8601String(),
                ];
            })
            ->values();

        return response()->json(['sources' => $sources]);
    }

    public function downloadM3uSource(M3uSource $m3uSource): StreamedResponse|JsonResponse
    {
        if (
            !$m3uSource->is_active ||
            $m3uSource->source_type !== 'file' ||
            !$m3uSource->file_path ||
            !Storage::disk('local')->exists($m3uSource->file_path)
        ) {
            return response()->json(['message' => 'File M3U tidak ditemukan.'], 404);
        }

        $safeName = preg_replace('/[^a-zA-Z0-9._-]+/', '_', $m3uSource->name) ?: 'playlist';

        return Storage::disk('local')->download(
            $m3uSource->file_path,
            $safeName . '.m3u',
            ['Content-Type' => 'audio/x-mpegurl; charset=utf-8']
        );
    }
}
