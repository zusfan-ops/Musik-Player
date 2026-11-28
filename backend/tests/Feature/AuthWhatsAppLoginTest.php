<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AuthWhatsAppLoginTest extends TestCase
{
    use RefreshDatabase;

    public function test_user_can_register_with_address_and_whatsapp_and_login_with_email_or_whatsapp(): void
    {
        $regRes = $this->postJson('/api/v1/auth/register', [
            'name' => 'Siti Rahma',
            'address' => 'Jl. Merdeka No. 10, Bandung',
            'phone' => '0812-3456-7890',
            'email' => 'siti@example.com',
            'password' => 'SecretPass123!',
        ]);

        $regRes->assertStatus(201)
            ->assertJsonPath('user.name', 'Siti Rahma')
            ->assertJsonPath('user.address', 'Jl. Merdeka No. 10, Bandung')
            ->assertJsonPath('user.phone', '081234567890');

        // Login with email
        $this->postJson('/api/v1/auth/login', [
            'login' => 'siti@example.com',
            'password' => 'SecretPass123!',
        ])->assertStatus(200)->assertJsonPath('user.email', 'siti@example.com');

        // Login with local WhatsApp format (0812...)
        $this->postJson('/api/v1/auth/login', [
            'login' => '081234567890',
            'password' => 'SecretPass123!',
        ])->assertStatus(200)->assertJsonPath('user.email', 'siti@example.com');

        // Login with international WhatsApp format (+62812...)
        $this->postJson('/api/v1/auth/login', [
            'login' => '+6281234567890',
            'password' => 'SecretPass123!',
        ])->assertStatus(200)->assertJsonPath('user.email', 'siti@example.com');

        // Wrong password returns 401
        $this->postJson('/api/v1/auth/login', [
            'login' => '081234567890',
            'password' => 'WrongPass123!',
        ])->assertStatus(401);
    }
}
