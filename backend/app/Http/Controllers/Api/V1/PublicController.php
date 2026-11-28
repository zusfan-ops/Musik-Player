<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\AnnouncementResource;
use App\Http\Resources\AppReleaseResource;
use App\Models\Announcement;
use App\Models\AppRelease;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
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
}
