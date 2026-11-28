<?php

namespace Tests\Feature;

use App\Models\AdCampaign;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class AdUploadAndAnalyticsTest extends TestCase
{
    use RefreshDatabase;

    public function test_admin_can_upload_ad_file_view_detailed_analytics_and_delete_file(): void
    {
        $admin = User::create([
            'name' => 'Super Admin',
            'email' => 'ad-admin@example.com',
            'password' => Hash::make('Password123!'),
            'role' => User::ROLE_SUPER_ADMIN,
            'is_active' => true,
        ]);

        $fakeImage = UploadedFile::fake()->image('promo-banner.png', 640, 360);

        $createRes = $this->actingAs($admin)->post('/admin/ads', [
            'title' => 'Promo Kopi Spesial',
            'description' => 'Diskon 30% hari ini',
            'media_type' => 'image',
            'media_file' => $fakeImage,
            'target_url' => 'https://mediacenter.ordr.my.id/kopi-spesial',
            'placement' => 'home_feed',
        ]);
        $createRes->assertRedirect();

        $ad = AdCampaign::where('title', 'Promo Kopi Spesial')->firstOrFail();
        $this->assertStringContainsString('/uploads/ads/', $ad->media_url);

        $filename = basename((string) parse_url($ad->media_url, PHP_URL_PATH));
        $localPath = public_path('uploads/ads/' . $filename);
        $this->assertTrue(File::exists($localPath));

        // Fetch ad & click from Flutter client
        $this->getJson('/api/v1/ads?placement=home_feed&platform=android&installation_id=dev-ad-1')
            ->assertStatus(200)
            ->assertJsonPath('data.0.id', $ad->id);

        $this->postJson('/api/v1/ads/' . $ad->id . '/click', [
            'platform' => 'android',
            'installation_id' => 'dev-ad-1',
        ])->assertStatus(200);

        $this->assertDatabaseHas('ad_events', [
            'ad_campaign_id' => $ad->id,
            'event_type' => 'impression',
            'platform' => 'android',
            'installation_id' => 'dev-ad-1',
        ]);
        $this->assertDatabaseHas('ad_events', [
            'ad_campaign_id' => $ad->id,
            'event_type' => 'click',
            'platform' => 'android',
            'installation_id' => 'dev-ad-1',
        ]);

        // Dashboard renders detailed analytics
        $dashRes = $this->actingAs($admin)->get('/admin');
        $dashRes->assertStatus(200);
        $dashRes->assertSee('Analitik Performa Iklan');
        $dashRes->assertSee('CTR Keseluruhan');
        $dashRes->assertSee('100%');

        // Delete ad also deletes uploaded file
        $this->actingAs($admin)->delete('/admin/ads/' . $ad->id)->assertRedirect();
        $this->assertFalse(File::exists($localPath));
    }
}
