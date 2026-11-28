<?php

namespace Tests\Feature;

use App\Models\AnalyticsEvent;
use App\Models\Announcement;
use App\Models\AppRelease;
use App\Models\SyncedPlaylist;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class ApiV1Test extends TestCase
{
    use RefreshDatabase;

    public function test_public_endpoints_and_etag_work_without_authentication(): void
    {
        Announcement::create([
            'title' => 'Info Uji',
            'body' => 'Pesan uji publik',
            'type' => 'info',
            'is_active' => true,
            'sort_order' => 1,
        ]);

        AppRelease::create([
            'version' => '1.12.1',
            'build_number' => 37,
            'platform' => 'android',
            'abi' => 'arm64-v8a',
            'download_url' => 'https://github.com/zusfan-ops/Musik-Player/releases/download/v1.12.1/M3UMusik-v1.12.1-arm64-v8a.apk',
            'is_active' => true,
            'published_at' => now(),
        ]);

        $this->getJson('/api/v1/health')
            ->assertOk()
            ->assertJsonPath('status', 'ok');

        $this->getJson('/api/v1/app-config')
            ->assertOk()
            ->assertJsonPath('guest_mode_enabled', true)
            ->assertJsonPath('sync_requires_opt_in', true);

        $annRes = $this->getJson('/api/v1/announcements')->assertOk();
        $etag = $annRes->headers->get('ETag');
        $this->assertNotEmpty($etag);

        $this->withHeader('If-None-Match', $etag)
            ->getJson('/api/v1/announcements')
            ->assertStatus(304);

        $this->getJson('/api/v1/releases/latest?platform=android&abi=arm64-v8a')
            ->assertOk()
            ->assertJsonPath('data.version', '1.12.1');
    }

    public function test_auth_device_export_and_account_deletion_flow(): void
    {
        $reg = $this->postJson('/api/v1/auth/register', [
            'name' => 'Budi',
            'email' => 'budi@example.com',
            'password' => 'SecretPass123!',
            'device_name' => 'Pixel 8',
            'platform' => 'android',
            'app_version' => '1.12.1',
        ])->assertCreated();

        $token = $reg->json('token');
        $this->assertNotEmpty($token);

        $this->withToken($token)
            ->getJson('/api/v1/me')
            ->assertOk()
            ->assertJsonPath('data.email', 'budi@example.com');

        $this->withToken($token)
            ->getJson('/api/v1/me/devices')
            ->assertOk()
            ->assertJsonCount(1, 'data');

        $this->withToken($token)
            ->getJson('/api/v1/me/export')
            ->assertOk()
            ->assertJsonPath('user.email', 'budi@example.com');

        $this->withToken($token)
            ->deleteJson('/api/v1/me')
            ->assertOk();

        $this->assertDatabaseMissing('users', ['email' => 'budi@example.com']);
    }

    public function test_sync_rejects_local_paths_detects_conflicts_and_blocks_idor(): void
    {
        $userA = User::factory()->create();
        $userB = User::factory()->create();

        $this->getJson('/api/v1/sync')->assertUnauthorized();

        // Reject local filesystem paths
        $this->actingAs($userA, 'sanctum')
            ->putJson('/api/v1/sync', [
                'playlists' => [
                    [
                        'client_uid' => 'pl-1',
                        'name' => 'C:\\Users\\Music\\Local',
                        'source_type' => 'metadata_only',
                    ],
                ],
            ])
            ->assertUnprocessable();

        // Valid metadata-only + remote URL sync
        $this->actingAs($userA, 'sanctum')
            ->putJson('/api/v1/sync', [
                'playlists' => [
                    [
                        'client_uid' => 'pl-1',
                        'name' => 'Favorit Kerja',
                        'source_type' => 'metadata_only',
                        'items' => [
                            [
                                'client_uid' => 'trk-1',
                                'title' => 'Lagu Santai',
                                'artist' => 'Artis A',
                                'duration_seconds' => 210,
                            ],
                        ],
                    ],
                ],
                'favorites' => [
                    [
                        'client_uid' => 'fav-1',
                        'title' => 'Lagu Santai',
                        'source_type' => 'local_metadata',
                    ],
                ],
                'settings' => [
                    'theme_mode' => 'dark',
                    'shuffle_enabled' => true,
                    'repeat_mode' => 'all',
                ],
            ])
            ->assertOk()
            ->assertJsonPath('sync_revision', 1);

        // Revision conflict returns 207 with server state without silent overwrite
        $this->actingAs($userA, 'sanctum')
            ->putJson('/api/v1/sync', [
                'playlists' => [
                    [
                        'client_uid' => 'pl-1',
                        'name' => 'Stale Overwrite',
                        'source_type' => 'metadata_only',
                        'expected_revision' => 0,
                    ],
                ],
            ])
            ->assertStatus(207)
            ->assertJsonCount(1, 'conflicts')
            ->assertJsonPath('conflicts.0.reason', 'REVISION_CONFLICT');

        $playlist = SyncedPlaylist::where('user_id', $userA->id)->firstOrFail();

        // IDOR protection: User B cannot read or delete User A's playlist
        $this->actingAs($userB, 'sanctum')
            ->getJson("/api/v1/playlists/{$playlist->id}")
            ->assertForbidden();

        $this->actingAs($userB, 'sanctum')
            ->deleteJson("/api/v1/playlists/{$playlist->id}")
            ->assertForbidden();
    }

    public function test_analytics_strips_forbidden_attributes_and_supports_deletion(): void
    {
        // Invalid event name rejected
        $this->postJson('/api/v1/analytics/events', [
            'installation_id' => 'inst-12345678',
            'events' => [
                ['event' => 'arbitrary_custom_event', 'platform' => 'android'],
            ],
        ])->assertUnprocessable();

        // Valid event stores allowed properties and strips forbidden ones
        $this->postJson('/api/v1/analytics/events', [
            'installation_id' => 'inst-12345678',
            'events' => [
                [
                    'event' => 'playlist_imported',
                    'platform' => 'android',
                    'app_version' => '1.12.1',
                    'properties' => [
                        'source' => 'url',
                        'playlist_url' => 'https://secret.example.com/private.m3u',
                        'file_path' => '/storage/emulated/0/Music/song.mp3',
                        'track_title' => 'Private Song',
                    ],
                ],
            ],
        ])->assertStatus(202);

        $event = AnalyticsEvent::firstOrFail();
        $this->assertSame(['source' => 'url'], $event->properties);

        $this->deleteJson('/api/v1/analytics/installation/inst-12345678')
            ->assertOk()
            ->assertJsonPath('deleted_count', 1);
    }

    public function test_feedback_endpoint_and_admin_rbac(): void
    {
        $this->postJson('/api/v1/feedback', [
            'category' => 'bug',
            'message' => 'Tombol repeat perlu diperjelas.',
            'platform' => 'windows',
            'app_version' => '1.12.1',
        ])->assertCreated();

        $regularUser = User::factory()->create(['role' => User::ROLE_USER]);
        $this->actingAs($regularUser)
            ->get('/admin')
            ->assertRedirect(route('admin.login'));

        $analyticsAdmin = User::factory()->create([
            'role' => User::ROLE_ANALYTICS_ADMIN,
            'password' => Hash::make('AdminPass123!'),
        ]);
        $this->actingAs($analyticsAdmin)
            ->get('/admin')
            ->assertOk();

        $this->actingAs($analyticsAdmin)
            ->post('/admin/announcements', [
                'title' => 'Unauthorized',
                'body' => 'Should fail',
                'type' => 'info',
            ])
            ->assertForbidden();

        $contentAdmin = User::factory()->create(['role' => User::ROLE_CONTENT_ADMIN]);
        $this->actingAs($contentAdmin)
            ->post('/admin/announcements', [
                'title' => 'Jadwal Maintenance',
                'body' => 'Server stabil.',
                'type' => 'maintenance',
            ])
            ->assertRedirect();

        $this->assertDatabaseHas('announcements', ['title' => 'Jadwal Maintenance']);
        $this->assertDatabaseHas('admin_audit_logs', ['action' => 'announcement_created']);
    }
}
