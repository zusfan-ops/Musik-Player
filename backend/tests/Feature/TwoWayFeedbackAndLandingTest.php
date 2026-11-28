<?php

namespace Tests\Feature;

use App\Models\FeedbackReport;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class TwoWayFeedbackAndLandingTest extends TestCase
{
    use RefreshDatabase;

    public function test_landing_page_includes_store_ecosystem_benefits_and_usage_guide(): void
    {
        $response = $this->get('/');
        $response->assertStatus(200);
        $response->assertSee('Ekosistem Toko Online');
        $response->assertSee('Panduan Penggunaan Fitur Baru');
        $response->assertSee('Cetak QR Code Toko');
        $response->assertSee('Komunikasi 2 Arah');
    }

    public function test_two_way_feedback_communication_and_idor_protection(): void
    {
        $admin = User::create([
            'name' => 'Super Admin',
            'email' => 'admin-support@example.com',
            'password' => Hash::make('Password123!'),
            'role' => User::ROLE_SUPER_ADMIN,
            'is_active' => true,
        ]);

        $user = User::create([
            'name' => 'Pemilik Kafe',
            'email' => 'kafe@example.com',
            'password' => Hash::make('Password123!'),
            'role' => User::ROLE_USER,
            'is_active' => true,
        ]);

        $otherUser = User::create([
            'name' => 'User Lain',
            'email' => 'other@example.com',
            'password' => Hash::make('Password123!'),
            'role' => User::ROLE_USER,
            'is_active' => true,
        ]);

        // User submits feature request
        $token = $user->createToken('test')->plainTextToken;
        $createRes = $this->withHeader('Authorization', 'Bearer ' . $token)
            ->postJson('/api/v1/feedback', [
                'installation_id' => 'device-abc-123',
                'category' => 'feature',
                'message' => 'Tolong tambahkan fitur cetak struk 80mm untuk POS.',
                'platform' => 'windows',
            ]);
        $createRes->assertStatus(201)
            ->assertJsonPath('data.category', 'feature')
            ->assertJsonPath('data.messages.0.sender_type', 'user');

        $ticketId = $createRes->json('data.id');

        // Other user cannot view or reply (IDOR protection)
        $this->app['auth']->forgetGuards();
        $otherToken = $otherUser->createToken('other')->plainTextToken;
        $this->withHeader('Authorization', 'Bearer ' . $otherToken)
            ->getJson('/api/v1/feedback/' . $ticketId)
            ->assertStatus(403);
        $this->withHeader('Authorization', 'Bearer ' . $otherToken)
            ->postJson('/api/v1/feedback/' . $ticketId . '/reply', [
                'message' => 'Coba bajak tiket',
            ])
            ->assertStatus(403);

        // Admin replies via admin panel
        $this->app['auth']->forgetGuards();
        $this->actingAs($admin)
            ->post('/admin/feedback/' . $ticketId . '/reply', [
                'body' => 'Siap, fitur cetak 80mm sedang kami kerjakan.',
                'status' => 'in_review',
            ])
            ->assertRedirect();

        // User fetches tickets and sees admin reply, then replies back
        $this->app['auth']->forgetGuards();
        $listRes = $this->withHeader('Authorization', 'Bearer ' . $token)
            ->getJson('/api/v1/feedback?installation_id=device-abc-123');
        $listRes->assertStatus(200)
            ->assertJsonPath('data.0.status', 'in_review')
            ->assertJsonPath('data.0.messages.1.sender_type', 'admin');

        $replyRes = $this->withHeader('Authorization', 'Bearer ' . $token)
            ->postJson('/api/v1/feedback/' . $ticketId . '/reply', [
                'message' => 'Terima kasih admin, ditunggu updatenya!',
            ]);
        $replyRes->assertStatus(201)
            ->assertJsonCount(3, 'data.messages')
            ->assertJsonPath('data.messages.2.sender_type', 'user');

        $this->assertDatabaseHas('feedback_reports', [
            'id' => $ticketId,
            'status' => 'in_review',
        ]);
    }
}
