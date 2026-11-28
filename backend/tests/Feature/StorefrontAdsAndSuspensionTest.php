<?php

namespace Tests\Feature;

use App\Models\Store;
use App\Models\StoreProduct;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class StorefrontAdsAndSuspensionTest extends TestCase
{
    use RefreshDatabase;

    public function test_register_with_store_creates_storefront_and_consumer_order_enters_pos_queue(): void
    {
        $reg = $this->postJson('/api/v1/auth/register', [
            'name' => 'Pemilik Kopi',
            'email' => 'kopi@example.com',
            'phone' => '081234567890',
            'password' => 'Password123!',
            'activate_store' => true,
            'store_name' => 'Kopi Nusantara',
            'store_slug' => 'kopi-nusantara',
            'store_type' => 'coffeeshop',
            'store_address' => 'Jl. Pemuda No. 10, Semarang',
            'tables_count' => 8,
        ])->assertCreated();

        $token = $reg->json('token');

        // Sync products from POS
        $this->withToken($token)->putJson('/api/v1/store/me', [
            'name' => 'Kopi Nusantara',
            'slug' => 'kopi-nusantara',
            'store_type' => 'coffeeshop',
            'address' => 'Jl. Pemuda No. 10, Semarang',
            'latitude' => -6.9825,
            'longitude' => 110.4091,
            'tables_count' => 8,
            'products' => [
                [
                    'client_uid' => 'prod-1',
                    'name' => 'Es Kopi Susu',
                    'category' => 'Kopi',
                    'price' => 18000,
                    'stock' => 25,
                    'unit' => 'cup',
                ],
            ],
        ])->assertOk();

        $product = StoreProduct::firstOrFail();

        // Public storefront renders
        $this->get('/kopi-nusantara?meja=3')
            ->assertOk()
            ->assertSee('Kopi Nusantara')
            ->assertSee('Es Kopi Susu');

        // Consumer places order with Name + WhatsApp
        $this->post('/kopi-nusantara/order', [
            'customer_name' => 'Budi Santoso',
            'customer_whatsapp' => '089911223344',
            'table_number' => 'Meja 3',
            'quantities' => [
                $product->id => 2,
            ],
        ])->assertRedirect();

        $this->assertDatabaseHas('store_customers', [
            'name' => 'Budi Santoso',
            'whatsapp' => '089911223344',
        ]);
        $this->assertDatabaseHas('store_orders', [
            'customer_name' => 'Budi Santoso',
            'table_number' => 'Meja 3',
            'total_amount' => 36000,
            'status' => 'queued',
        ]);

        // Owner sees order in POS queue
        $this->withToken($token)->getJson('/api/v1/store/orders')
            ->assertOk()
            ->assertJsonFragment(['customer_name' => 'Budi Santoso', 'status' => 'queued']);
    }

    public function test_coffeeshop_booking_requires_registered_user_and_suspension_hides_store(): void
    {
        $owner = User::factory()->create(['is_active' => true]);
        $store = Store::create([
            'user_id' => $owner->id,
            'name' => 'Cafe Senja',
            'slug' => 'cafe-senja',
            'store_type' => 'coffeeshop',
            'tables_count' => 5,
            'is_active' => true,
        ]);

        // Guest cannot book table
        $this->postJson('/api/v1/stores/cafe-senja/bookings', [
            'table_number' => 'Meja 2',
            'guests_count' => 4,
            'booking_time' => now()->addDay()->toIso8601String(),
            'customer_whatsapp' => '081111222233',
        ])->assertUnauthorized();

        // Registered user can book table
        $customer = User::factory()->create(['is_active' => true]);
        $custToken = $customer->createToken('app')->plainTextToken;
        $this->withToken($custToken)->postJson('/api/v1/stores/cafe-senja/bookings', [
            'table_number' => 'Meja 2',
            'guests_count' => 4,
            'booking_time' => now()->addDay()->toIso8601String(),
            'customer_whatsapp' => '081111222233',
        ])->assertCreated();

        // Super admin suspends owner temporarily -> store disappears from public & storefront returns 404
        $admin = User::factory()->create(['role' => User::ROLE_SUPER_ADMIN, 'is_active' => true]);
        $this->actingAs($admin)->post(route('admin.users.suspend', $owner), [
            'mode' => 'temporary',
            'days' => 7,
            'reason' => 'Spam',
        ])->assertRedirect();

        $this->get('/cafe-senja')->assertNotFound();
        $this->getJson('/api/v1/stores/discover')
            ->assertOk()
            ->assertJsonMissing(['slug' => 'cafe-senja']);
    }

    public function test_admin_can_create_native_ads_and_public_api_serves_them(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_CONTENT_ADMIN, 'is_active' => true]);
        $this->actingAs($admin)->post(route('admin.ads.store'), [
            'title' => 'Promo Hosting UMKM',
            'media_type' => 'image',
            'media_url' => 'https://cdn.example.com/ad.jpg',
            'target_url' => 'https://example.com/promo',
            'placement' => 'home_feed',
        ])->assertRedirect();

        $this->getJson('/api/v1/ads?placement=home_feed')
            ->assertOk()
            ->assertJsonFragment(['title' => 'Promo Hosting UMKM', 'media_type' => 'image']);
    }
}
