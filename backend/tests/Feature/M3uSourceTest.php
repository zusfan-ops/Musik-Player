<?php

namespace Tests\Feature;

use App\Models\M3uSource;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class M3uSourceTest extends TestCase
{
    use RefreshDatabase;

    public function test_admin_can_create_url_and_file_m3u_sources_and_public_api_serves_them(): void
    {
        Storage::fake('local');

        $admin = User::factory()->create([
            'role' => User::ROLE_CONTENT_ADMIN,
            'is_active' => true,
        ]);

        // 1. Add URL M3U source
        $resUrl = $this->actingAs($admin)->post(route('admin.m3u-sources.store'), [
            'name' => 'TV Nasional Backend',
            'category' => 'TV & CCTV',
            'source_type' => 'url',
            'source_url' => 'https://example.com/tv.m3u',
        ]);
        $resUrl->assertRedirect();

        // 2. Upload .m3u file
        $file = UploadedFile::fake()->createWithContent(
            'radio.m3u',
            "#EXTM3U\n#EXTINF:-1,Radio Satu\nhttps://stream.example.com/radio.mp3\n"
        );
        $resFile = $this->actingAs($admin)->post(route('admin.m3u-sources.store'), [
            'name' => 'Radio Backend',
            'category' => 'Radio',
            'source_type' => 'file',
            'm3u_file' => $file,
        ]);
        $resFile->assertRedirect();

        $this->assertDatabaseCount('m3u_sources', 2);

        // 3. Public API lists both active sources
        $apiRes = $this->getJson('/api/v1/m3u-sources');
        $apiRes->assertOk()
            ->assertJsonCount(2, 'sources')
            ->assertJsonFragment(['name' => 'TV Nasional Backend', 'category' => 'TV & CCTV'])
            ->assertJsonFragment(['name' => 'Radio Backend', 'category' => 'Radio']);

        // 4. Download endpoint serves uploaded .m3u file
        $fileSource = M3uSource::where('source_type', 'file')->firstOrFail();
        $dlRes = $this->get("/api/v1/m3u-sources/{$fileSource->id}/download");
        $dlRes->assertOk();

        // 5. Admin dashboard renders sidebar & M3U sources
        $dashRes = $this->actingAs($admin)->get(route('admin.dashboard'));
        $dashRes->assertOk()
            ->assertSee('Sumber M3U')
            ->assertSee('TV Nasional Backend');
    }
}
