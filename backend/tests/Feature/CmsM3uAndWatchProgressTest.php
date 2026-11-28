<?php

namespace Tests\Feature;

use App\Models\M3uSource;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class CmsM3uAndWatchProgressTest extends TestCase
{
    use RefreshDatabase;

    public function test_cms_draft_publish_and_rollback_workflow(): void
    {
        $admin = User::factory()->create([
            'role' => User::ROLE_CONTENT_ADMIN,
            'is_active' => true,
        ]);

        // 1. Save as draft -> must NOT appear in public /api/v1/m3u-sources
        $this->actingAs($admin)->post(route('admin.m3u-sources.store'), [
            'name' => 'Draft Channel',
            'category' => 'TV & CCTV',
            'region' => 'Jawa Tengah',
            'city' => 'Semarang',
            'language' => 'Indonesia',
            'status' => 'draft',
            'source_type' => 'url',
            'source_url' => 'https://example.com/draft.m3u',
        ])->assertRedirect();

        $this->getJson('/api/v1/m3u-sources')
            ->assertOk()
            ->assertJsonCount(0, 'sources');

        // 2. Publish -> now visible in public API with region/city/language
        $src = M3uSource::firstOrFail();
        $this->actingAs($admin)
            ->post(route('admin.m3u-sources.publish', $src))
            ->assertRedirect();

        $this->getJson('/api/v1/m3u-sources')
            ->assertOk()
            ->assertJsonCount(1, 'sources')
            ->assertJsonFragment([
                'name' => 'Draft Channel',
                'region' => 'Jawa Tengah',
                'city' => 'Semarang',
                'language' => 'Indonesia',
                'stream_status' => 'online',
            ]);

        // 3. Rollback to v1 (draft) -> hidden from public API again
        $v1 = $src->versions()->where('version_number', 1)->firstOrFail();
        $this->actingAs($admin)
            ->post(route('admin.m3u-sources.rollback', [$src, $v1]))
            ->assertRedirect();

        $this->getJson('/api/v1/m3u-sources')
            ->assertOk()
            ->assertJsonCount(0, 'sources');
    }

    public function test_watch_progress_sync_requires_auth_and_sanitizes_urls(): void
    {
        $this->getJson('/api/v1/watch-progress')->assertUnauthorized();

        $user = User::factory()->create(['is_active' => true]);
        $token = $user->createToken('test-device')->plainTextToken;

        $this->withToken($token)->putJson('/api/v1/watch-progress', [
            'items' => [
                [
                    'content_key' => 'jf_movie_42',
                    'title' => 'Film Uji',
                    'content_type' => 'video',
                    'position_seconds' => 320,
                    'duration_seconds' => 5400,
                    'stream_url' => 'https://cinema.example.com/video/42',
                ],
                [
                    'content_key' => 'local_file_99',
                    'title' => 'File Lokal',
                    'content_type' => 'video',
                    'position_seconds' => 120,
                    'duration_seconds' => 1800,
                    'stream_url' => 'http://127.0.0.1/private/secret.mp4',
                ],
            ],
        ])->assertOk()->assertJson(['saved' => 2]);

        $res = $this->withToken($token)->getJson('/api/v1/watch-progress')->assertOk();
        $res->assertJsonFragment([
            'content_key' => 'jf_movie_42',
            'position_seconds' => 320,
            'stream_url' => 'https://cinema.example.com/video/42',
        ]);
        // localhost stream_url must be sanitized to null
        $res->assertJsonFragment([
            'content_key' => 'local_file_99',
            'stream_url' => null,
        ]);
    }
}
