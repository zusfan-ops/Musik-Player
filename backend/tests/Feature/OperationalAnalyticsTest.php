<?php

namespace Tests\Feature;

use App\Models\AnalyticsEvent;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class OperationalAnalyticsTest extends TestCase
{
    use RefreshDatabase;

    public function test_operational_analytics_aggregates_dau_searches_playlists_channels_errors_and_sync_failures(): void
    {
        $admin = User::factory()->create([
            'role' => User::ROLE_ANALYTICS_ADMIN,
            'is_active' => true,
        ]);

        $this->postJson('/api/v1/analytics/events', [
            'installation_id' => 'inst_ops_001',
            'events' => [
                [
                    'event' => 'catalog_searched',
                    'platform' => 'android',
                    'app_version' => '1.12.1',
                    'properties' => ['query_term' => 'jakarta'],
                ],
                [
                    'event' => 'playlist_opened',
                    'platform' => 'android_tv',
                    'app_version' => '1.12.1',
                    'properties' => ['catalog_name' => 'TV Indonesia'],
                ],
                [
                    'event' => 'channel_opened',
                    'platform' => 'android_tv',
                    'app_version' => '1.12.1',
                    'properties' => ['channel_name' => 'TVRI Nasional'],
                ],
                [
                    'event' => 'playback_error',
                    'platform' => 'android',
                    'app_version' => '1.12.1',
                    'properties' => ['error_code' => 'EXOPLAYER_SOURCE_ERROR'],
                ],
                [
                    'event' => 'sync_failed',
                    'platform' => 'windows',
                    'app_version' => '1.12.1',
                    'properties' => ['sync_target' => 'github_m3u'],
                ],
            ],
        ])->assertStatus(202);

        $this->actingAs($admin)
            ->get(route('admin.dashboard'))
            ->assertOk()
            ->assertSee('Aktif Harian (7 Hari Terakhir / DAU)')
            ->assertSee('jakarta')
            ->assertSee('TV Indonesia')
            ->assertSee('TVRI Nasional')
            ->assertSee('EXOPLAYER_SOURCE_ERROR')
            ->assertSee('github_m3u');
    }

    public function test_analytics_retention_prune_deletes_old_events_and_keeps_recent(): void
    {
        $admin = User::factory()->create([
            'role' => User::ROLE_ANALYTICS_ADMIN,
            'is_active' => true,
        ]);

        AnalyticsEvent::create([
            'installation_id' => 'inst_old_999',
            'event_name' => 'app_open',
            'platform' => 'android',
            'occurred_at' => now()->subDays(120),
        ]);
        AnalyticsEvent::create([
            'installation_id' => 'inst_new_111',
            'event_name' => 'app_open',
            'platform' => 'android',
            'occurred_at' => now()->subDays(2),
        ]);

        $this->actingAs($admin)
            ->post(route('admin.analytics.prune'))
            ->assertRedirect();

        $this->assertDatabaseMissing('analytics_events', ['installation_id' => 'inst_old_999']);
        $this->assertDatabaseHas('analytics_events', ['installation_id' => 'inst_new_111']);
    }
}
