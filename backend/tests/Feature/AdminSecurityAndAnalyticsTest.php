<?php

namespace Tests\Feature;

use App\Models\AnalyticsEvent;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AdminSecurityAndAnalyticsTest extends TestCase
{
    use RefreshDatabase;

    public function test_security_headers_are_present_on_responses(): void
    {
        $res = $this->get('/api/v1/health');
        $res->assertOk()
            ->assertHeader('X-Frame-Options', 'DENY')
            ->assertHeader('X-Content-Type-Options', 'nosniff')
            ->assertHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
    }

    public function test_admin_login_enforces_single_use_math_captcha(): void
    {
        $admin = User::factory()->create([
            'email' => 'admin-sec@example.com',
            'password' => 'StrongPassword123!',
            'role' => User::ROLE_SUPER_ADMIN,
            'is_active' => true,
        ]);

        // Load login form to initialize session CAPTCHA
        $this->get(route('admin.login'))->assertOk()->assertSee('Verifikasi Keamanan');
        $answer = session('admin_captcha_answer');
        $this->assertIsInt($answer);

        // Wrong captcha is rejected
        $this->post(route('admin.login.submit'), [
            'email' => $admin->email,
            'password' => 'StrongPassword123!',
            'captcha' => $answer + 5,
        ])->assertSessionHasErrors('captcha');
        $this->assertGuest();

        // Replay of old captcha fails because it was invalidated on previous attempt
        $this->post(route('admin.login.submit'), [
            'email' => $admin->email,
            'password' => 'StrongPassword123!',
            'captcha' => $answer,
        ])->assertSessionHasErrors('captcha');
        $this->assertGuest();

        // Fresh captcha succeeds
        $this->get(route('admin.login'))->assertOk();
        $freshAnswer = session('admin_captcha_answer');
        $this->post(route('admin.login.submit'), [
            'email' => $admin->email,
            'password' => 'StrongPassword123!',
            'captcha' => $freshAnswer,
        ])->assertRedirect(route('admin.dashboard'));
        $this->assertAuthenticatedAs($admin);
    }

    public function test_analytics_dashboard_computes_duration_and_feedback_accepts_feature_and_complaint(): void
    {
        $admin = User::factory()->create([
            'role' => User::ROLE_ANALYTICS_ADMIN,
            'is_active' => true,
        ]);

        AnalyticsEvent::create([
            'installation_id' => 'inst_12345678',
            'event_name' => 'app_session_ended',
            'platform' => 'android',
            'app_version' => '1.12.1',
            'properties' => ['duration_seconds' => 185],
            'occurred_at' => now(),
        ]);

        $this->actingAs($admin)
            ->get(route('admin.dashboard'))
            ->assertOk()
            ->assertSee('Analisa Pengguna')
            ->assertSee('3 mnt 5 dtk');

        $this->postJson('/api/v1/feedback', [
            'category' => 'feature',
            'message' => 'Tolong tambahkan sleep timer otomatis.',
            'platform' => 'android',
        ])->assertCreated();

        $this->postJson('/api/v1/feedback', [
            'category' => 'complaint',
            'message' => 'Stream kadang lambat di jaringan seluler.',
            'platform' => 'android',
        ])->assertCreated();

        $this->actingAs($admin)
            ->get(route('admin.dashboard'))
            ->assertOk()
            ->assertSee('Stream kadang lambat di jaringan seluler.');
    }
}
