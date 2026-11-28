<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\SyncFavoriteResource;
use App\Http\Resources\SyncPlaylistResource;
use App\Http\Resources\SyncSettingResource;
use App\Models\SyncedFavorite;
use App\Models\SyncedPlaylist;
use App\Models\SyncedPlaylistItem;
use App\Models\SyncedSetting;
use App\Support\SyncSanitizer;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class SyncController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        $playlists = $user->syncedPlaylists()->with('items')->orderBy('name')->get();
        $favorites = $user->syncedFavorites()->orderBy('title')->get();
        $setting = $user->syncedSetting()->first();

        return response()->json([
            'sync_revision' => $user->sync_revision,
            'playlists' => SyncPlaylistResource::collection($playlists),
            'favorites' => SyncFavoriteResource::collection($favorites),
            'settings' => $setting ? new SyncSettingResource($setting) : null,
        ]);
    }

    public function upsert(Request $request): JsonResponse
    {
        $user = $request->user();
        $maxPlaylists = config('mediacenter.max_playlists_per_user', 100);
        $maxItems = config('mediacenter.max_items_per_playlist', 500);
        $maxFavorites = config('mediacenter.max_favorites_per_user', 1000);

        $data = $request->validate([
            'playlists' => ['sometimes', 'array', "max:$maxPlaylists"],
            'playlists.*.client_uid' => ['required', 'string', 'max:80'],
            'playlists.*.name' => ['required', 'string', 'max:160'],
            'playlists.*.source_type' => ['required', 'string', 'in:url,metadata_only'],
            'playlists.*.source_url' => ['nullable', 'string', 'max:1024'],
            'playlists.*.expected_revision' => ['nullable', 'integer', 'min:0'],
            'playlists.*.is_enabled' => ['sometimes', 'boolean'],
            'playlists.*.client_updated_at' => ['nullable', 'date'],
            'playlists.*.items' => ['sometimes', 'array', "max:$maxItems"],
            'playlists.*.items.*.client_uid' => ['required', 'string', 'max:80'],
            'playlists.*.items.*.title' => ['required', 'string', 'max:200'],
            'playlists.*.items.*.artist' => ['nullable', 'string', 'max:160'],
            'playlists.*.items.*.album' => ['nullable', 'string', 'max:160'],
            'playlists.*.items.*.group_title' => ['nullable', 'string', 'max:160'],
            'playlists.*.items.*.duration_seconds' => ['nullable', 'integer', 'min:0'],
            'playlists.*.items.*.metadata_hash' => ['nullable', 'string', 'max:64'],
            'playlists.*.items.*.stream_url' => ['nullable', 'string', 'max:1024'],
            'playlists.*.items.*.is_video' => ['sometimes', 'boolean'],
            'playlists.*.items.*.last_position_seconds' => ['sometimes', 'integer', 'min:0'],

            'favorites' => ['sometimes', 'array', "max:$maxFavorites"],
            'favorites.*.client_uid' => ['required', 'string', 'max:80'],
            'favorites.*.title' => ['required', 'string', 'max:200'],
            'favorites.*.artist' => ['nullable', 'string', 'max:160'],
            'favorites.*.album' => ['nullable', 'string', 'max:160'],
            'favorites.*.duration_seconds' => ['nullable', 'integer', 'min:0'],
            'favorites.*.metadata_hash' => ['nullable', 'string', 'max:64'],
            'favorites.*.source_type' => ['required', 'string', 'in:local_metadata,remote_url'],
            'favorites.*.stream_url' => ['nullable', 'string', 'max:1024'],
            'favorites.*.is_video' => ['sometimes', 'boolean'],
            'favorites.*.client_updated_at' => ['nullable', 'date'],

            'settings' => ['sometimes', 'array'],
            'settings.theme_mode' => ['sometimes', 'string', 'in:dark,light,system'],
            'settings.shuffle_enabled' => ['sometimes', 'boolean'],
            'settings.repeat_mode' => ['sometimes', 'string', 'in:off,one,all'],
            'settings.eq_preset' => ['nullable', 'string', 'max:40'],
            'settings.playback_speed' => ['sometimes', 'numeric', 'min:0.25', 'max:3.0'],
            'settings.extra_json' => ['sometimes', 'array'],
            'settings.client_updated_at' => ['nullable', 'date'],
        ]);

        // Pre-validate all URLs & reject any local filesystem paths before opening transaction
        foreach ($data['playlists'] ?? [] as $pIdx => $pl) {
            SyncSanitizer::assertNoLocalPath($pl['name'] ?? null, "playlists.$pIdx.name");
            SyncSanitizer::sanitizeRemoteUrl($pl['source_url'] ?? null, "playlists.$pIdx.source_url");
            foreach ($pl['items'] ?? [] as $iIdx => $item) {
                SyncSanitizer::assertNoLocalPath($item['title'] ?? null, "playlists.$pIdx.items.$iIdx.title");
                SyncSanitizer::sanitizeRemoteUrl($item['stream_url'] ?? null, "playlists.$pIdx.items.$iIdx.stream_url");
            }
        }
        foreach ($data['favorites'] ?? [] as $fIdx => $fav) {
            SyncSanitizer::assertNoLocalPath($fav['title'] ?? null, "favorites.$fIdx.title");
            SyncSanitizer::sanitizeRemoteUrl($fav['stream_url'] ?? null, "favorites.$fIdx.stream_url");
        }

        $conflicts = [];

        DB::transaction(function () use ($user, $data, &$conflicts) {
            foreach ($data['playlists'] ?? [] as $plData) {
                $existing = SyncedPlaylist::where('user_id', $user->id)
                    ->where('client_uid', $plData['client_uid'])
                    ->first();

                if (
                    $existing &&
                    isset($plData['expected_revision']) &&
                    (int) $plData['expected_revision'] < $existing->revision
                ) {
                    $conflicts[] = [
                        'entity' => 'playlist',
                        'client_uid' => $existing->client_uid,
                        'reason' => 'REVISION_CONFLICT',
                        'server_revision' => $existing->revision,
                        'server_state' => new SyncPlaylistResource($existing->load('items')),
                    ];
                    continue;
                }

                $playlist = $existing ?? new SyncedPlaylist([
                    'user_id' => $user->id,
                    'client_uid' => $plData['client_uid'],
                    'revision' => 0,
                ]);
                $playlist->name = $plData['name'];
                $playlist->source_type = $plData['source_type'];
                $playlist->source_url = SyncSanitizer::sanitizeRemoteUrl($plData['source_url'] ?? null, 'source_url');
                $playlist->is_enabled = $plData['is_enabled'] ?? true;
                $playlist->client_updated_at = $plData['client_updated_at'] ?? now();
                $playlist->revision = ($playlist->revision ?? 0) + 1;
                $playlist->save();

                if (array_key_exists('items', $plData)) {
                    $playlist->items()->delete();
                    foreach ($plData['items'] as $pos => $item) {
                        SyncedPlaylistItem::create([
                            'synced_playlist_id' => $playlist->id,
                            'client_uid' => $item['client_uid'],
                            'position' => $pos,
                            'title' => $item['title'],
                            'artist' => $item['artist'] ?? null,
                            'album' => $item['album'] ?? null,
                            'group_title' => $item['group_title'] ?? null,
                            'duration_seconds' => $item['duration_seconds'] ?? null,
                            'metadata_hash' => $item['metadata_hash'] ?? null,
                            'stream_url' => SyncSanitizer::sanitizeRemoteUrl($item['stream_url'] ?? null, 'stream_url'),
                            'is_video' => $item['is_video'] ?? false,
                            'last_position_seconds' => $item['last_position_seconds'] ?? 0,
                        ]);
                    }
                }
            }

            foreach ($data['favorites'] ?? [] as $fav) {
                SyncedFavorite::updateOrCreate(
                    ['user_id' => $user->id, 'client_uid' => $fav['client_uid']],
                    [
                        'title' => $fav['title'],
                        'artist' => $fav['artist'] ?? null,
                        'album' => $fav['album'] ?? null,
                        'duration_seconds' => $fav['duration_seconds'] ?? null,
                        'metadata_hash' => $fav['metadata_hash'] ?? null,
                        'source_type' => $fav['source_type'],
                        'stream_url' => SyncSanitizer::sanitizeRemoteUrl($fav['stream_url'] ?? null, 'stream_url'),
                        'is_video' => $fav['is_video'] ?? false,
                        'client_updated_at' => $fav['client_updated_at'] ?? now(),
                    ]
                );
            }

            if (isset($data['settings'])) {
                $s = $data['settings'];
                $existingSetting = SyncedSetting::where('user_id', $user->id)->first();
                SyncedSetting::updateOrCreate(
                    ['user_id' => $user->id],
                    [
                        'theme_mode' => $s['theme_mode'] ?? $existingSetting?->theme_mode ?? 'system',
                        'shuffle_enabled' => $s['shuffle_enabled'] ?? $existingSetting?->shuffle_enabled ?? false,
                        'repeat_mode' => $s['repeat_mode'] ?? $existingSetting?->repeat_mode ?? 'off',
                        'eq_preset' => $s['eq_preset'] ?? $existingSetting?->eq_preset,
                        'playback_speed' => $s['playback_speed'] ?? $existingSetting?->playback_speed ?? 1.0,
                        'extra_json' => SyncSanitizer::sanitizeExtraMap($s['extra_json'] ?? []),
                        'revision' => ($existingSetting?->revision ?? 0) + 1,
                        'client_updated_at' => $s['client_updated_at'] ?? now(),
                    ]
                );
            }

            $user->increment('sync_revision');
        });

        $user->refresh();
        return response()->json([
            'sync_revision' => $user->sync_revision,
            'conflicts' => $conflicts,
            'playlists' => SyncPlaylistResource::collection(
                $user->syncedPlaylists()->with('items')->get()
            ),
            'favorites' => SyncFavoriteResource::collection(
                $user->syncedFavorites()->get()
            ),
            'settings' => ($st = $user->syncedSetting()->first()) ? new SyncSettingResource($st) : null,
        ], empty($conflicts) ? 200 : 207);
    }

    public function playlistsIndex(Request $request): JsonResponse
    {
        $playlists = $request->user()->syncedPlaylists()->with('items')->paginate(25);
        return response()->json([
            'data' => SyncPlaylistResource::collection($playlists),
            'meta' => [
                'current_page' => $playlists->currentPage(),
                'last_page' => $playlists->lastPage(),
                'total' => $playlists->total(),
            ],
        ]);
    }

    public function playlistsStore(Request $request): JsonResponse
    {
        $user = $request->user();
        $maxPlaylists = config('mediacenter.max_playlists_per_user', 100);
        if ($user->syncedPlaylists()->count() >= $maxPlaylists) {
            return response()->json([
                'message' => 'Batas jumlah playlist tersinkronisasi tercapai.',
                'error_code' => 'PLAYLIST_LIMIT_REACHED',
            ], 422);
        }

        $data = $request->validate([
            'client_uid' => ['required', 'string', 'max:80'],
            'name' => ['required', 'string', 'max:160'],
            'source_type' => ['required', 'string', 'in:url,metadata_only'],
            'source_url' => ['nullable', 'string', 'max:1024'],
        ]);

        SyncSanitizer::assertNoLocalPath($data['name'], 'name');
        $cleanUrl = SyncSanitizer::sanitizeRemoteUrl($data['source_url'] ?? null, 'source_url');

        $playlist = SyncedPlaylist::updateOrCreate(
            ['user_id' => $user->id, 'client_uid' => $data['client_uid']],
            [
                'name' => $data['name'],
                'source_type' => $data['source_type'],
                'source_url' => $cleanUrl,
                'client_updated_at' => now(),
                'revision' => 1,
            ]
        );

        return response()->json(['data' => new SyncPlaylistResource($playlist->load('items'))], 201);
    }

    public function playlistsShow(Request $request, SyncedPlaylist $playlist): JsonResponse
    {
        if ($playlist->user_id !== $request->user()->id) {
            return response()->json(['message' => 'Akses ditolak.'], 403);
        }
        return response()->json(['data' => new SyncPlaylistResource($playlist->load('items'))]);
    }

    public function playlistsUpdate(Request $request, SyncedPlaylist $playlist): JsonResponse
    {
        if ($playlist->user_id !== $request->user()->id) {
            return response()->json(['message' => 'Akses ditolak.'], 403);
        }

        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:160'],
            'source_type' => ['sometimes', 'string', 'in:url,metadata_only'],
            'source_url' => ['nullable', 'string', 'max:1024'],
            'expected_revision' => ['nullable', 'integer', 'min:0'],
        ]);

        if (isset($data['expected_revision']) && (int) $data['expected_revision'] !== $playlist->revision) {
            return response()->json([
                'message' => 'Konflik revisi playlist.',
                'error_code' => 'REVISION_CONFLICT',
                'server_state' => new SyncPlaylistResource($playlist->load('items')),
            ], 409);
        }

        if (isset($data['name'])) {
            SyncSanitizer::assertNoLocalPath($data['name'], 'name');
            $playlist->name = $data['name'];
        }
        if (array_key_exists('source_url', $data)) {
            $playlist->source_url = SyncSanitizer::sanitizeRemoteUrl($data['source_url'], 'source_url');
        }
        if (isset($data['source_type'])) {
            $playlist->source_type = $data['source_type'];
        }
        $playlist->revision++;
        $playlist->client_updated_at = now();
        $playlist->save();

        return response()->json(['data' => new SyncPlaylistResource($playlist->load('items'))]);
    }

    public function playlistsDestroy(Request $request, SyncedPlaylist $playlist): JsonResponse
    {
        if ($playlist->user_id !== $request->user()->id) {
            return response()->json(['message' => 'Akses ditolak.'], 403);
        }
        $playlist->delete();
        return response()->json(['message' => 'Playlist dihapus dari sinkronisasi.']);
    }

    public function destroySyncData(Request $request): JsonResponse
    {
        $user = $request->user();
        DB::transaction(function () use ($user) {
            $user->syncedPlaylists()->forceDelete();
            $user->syncedFavorites()->delete();
            $user->syncedSetting()->delete();
            $user->update(['sync_revision' => 0]);
        });

        return response()->json(['message' => 'Seluruh data sinkronisasi telah dihapus.']);
    }
}
