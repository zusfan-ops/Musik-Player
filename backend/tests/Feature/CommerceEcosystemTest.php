<?php

namespace Tests\Feature;

use App\Models\AdCampaign;
use App\Models\Store;
use App\Models\StoreProduct;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class CommerceEcosystemTest extends TestCase
{
    use RefreshDatabase;

    public function test_voucher_review_jukebox_maps_qr_qris_pin_finance_boost_and_nearby_discover(): void
    {
        $admin = User::create([
            'name' => 'Admin',
            'email' => 'eco-admin@example.com',
            'password' => Hash::make('Password123!'),
            'role' => User::ROLE_SUPER_ADMIN,
            'is_active' => true,
        ]);

        $owner = User::create([
            'name' => 'Owner Kafe',
            'email' => 'eco-owner@example.com',
            'password' => Hash::make('Password123!'),
            'role' => User::ROLE_USER,
            'is_active' => true,
        ]);

        $token = $owner->createToken('pos')->plainTextToken;

        // 1. Upsert store with Google Maps review URL, opening hours, PIN, GPS
        $this->withHeader('Authorization', 'Bearer ' . $token)
            ->putJson('/api/v1/store/me', [
                'name' => 'Kopi Nusantara',
                'slug' => 'kopi-nusantara',
                'store_type' => 'coffeeshop',
                'address' => 'Jl. Sudirman No. 1',
                'latitude' => -6.2000,
                'longitude' => 106.8166,
                'tables_count' => 8,
                'google_maps_review_url' => 'https://g.page/r/kopi-nusantara/review',
                'opening_hours' => '08:00-22:00',
                'is_open' => true,
                'staff_pin' => '1234',
                'products' => [
                    [
                        'client_uid' => 'p-1',
                        'name' => 'Es Kopi Susu',
                        'category' => 'Kopi',
                        'price' => 20000,
                        'stock' => 50,
                        'unit' => 'cup',
                        'is_active' => true,
                    ],
                ],
            ])
            ->assertStatus(200);

        $store = Store::where('slug', 'kopi-nusantara')->firstOrFail();
        $product = StoreProduct::where('store_id', $store->id)->firstOrFail();

        // 2. Verify staff PIN
        $this->app['auth']->forgetGuards();
        $this->withHeader('Authorization', 'Bearer ' . $token)
            ->postJson('/api/v1/store/me/verify-pin', ['pin' => '1234'])
            ->assertStatus(200)
            ->assertJsonPath('valid', true);
        $this->withHeader('Authorization', 'Bearer ' . $token)
            ->postJson('/api/v1/store/me/verify-pin', ['pin' => '9999'])
            ->assertStatus(403);

        // 3. Upload QRIS
        $qrisRes = $this->withHeader('Authorization', 'Bearer ' . $token)
            ->post('/api/v1/store/me/qris', [
                'qris_file' => UploadedFile::fake()->image('qris.png', 300, 300),
            ]);
        $qrisRes->assertStatus(200);
        $qrisUrl = $qrisRes->json('data.qris_image_url');
        $qrisFile = public_path('uploads/qris/' . basename((string) parse_url($qrisUrl, PHP_URL_PATH)));
        $this->assertTrue(File::exists($qrisFile));
        File::delete($qrisFile);

        // 4. Create Voucher & place order with voucher on storefront
        $this->withHeader('Authorization', 'Bearer ' . $token)
            ->postJson('/api/v1/store/vouchers', [
                'code' => 'HEMAT20',
                'discount_type' => 'percent',
                'discount_value' => 20,
                'min_order' => 10000,
                'max_uses' => 5,
            ])
            ->assertStatus(201);

        $this->post('/kopi-nusantara/order', [
            'customer_name' => 'Budi',
            'customer_whatsapp' => '081234567890',
            'table_number' => 'Meja 3',
            'voucher_code' => 'HEMAT20',
            'quantities' => [$product->id => 2], // 40,000 - 20% = 32,000
        ])->assertRedirect();

        $this->assertDatabaseHas('store_orders', [
            'store_id' => $store->id,
            'voucher_code' => 'HEMAT20',
            'discount_amount' => 8000.0,
            'total_amount' => 32000.0,
        ]);

        // 5. Verified review & Google Maps QR on storefront
        $this->post('/kopi-nusantara/review', [
            'reviewer_name' => 'Budi',
            'reviewer_whatsapp' => '081234567890',
            'rating' => 5,
            'comment' => 'Kopi mantap!',
        ])->assertRedirect();

        $this->assertDatabaseHas('store_reviews', [
            'store_id' => $store->id,
            'is_verified_order' => true,
            'rating' => 5,
        ]);

        // 6. Cafe Jukebox request + Now Playing
        $this->post('/kopi-nusantara/jukebox', [
            'requester_name' => 'Budi',
            'table_number' => 'Meja 3',
            'song_title' => 'Separuh Aku',
            'artist_name' => 'Noah',
        ])->assertRedirect();

        $this->withHeader('Authorization', 'Bearer ' . $token)
            ->postJson('/api/v1/store/jukebox/now-playing', [
                'title' => 'Laskar Pelangi',
                'artist' => 'Nidji',
            ])
            ->assertStatus(200);

        $storePage = $this->get('/kopi-nusantara');
        $storePage->assertStatus(200)
            ->assertSee('Laskar Pelangi')
            ->assertSee('Beri Rating di Google Maps')
            ->assertSee('https://g.page/r/kopi-nusantara/review');

        // 7. Cloud Finance Sync
        $this->withHeader('Authorization', 'Bearer ' . $token)
            ->postJson('/api/v1/store/finance/sync', [
                'entries' => [
                    [
                        'client_uid' => 'fin-1',
                        'entry_type' => 'income',
                        'category' => 'Penjualan POS',
                        'amount' => 32000,
                        'payment_account' => 'QRIS',
                        'description' => 'Order Web',
                    ],
                ],
            ])
            ->assertStatus(200)
            ->assertJsonCount(1, 'data');

        // 8. Boost Toko Ad submission & Admin approval
        $boostRes = $this->withHeader('Authorization', 'Bearer ' . $token)
            ->postJson('/api/v1/store/boost-ad', [
                'title' => 'Promo Kopi Nusantara',
                'media_type' => 'image',
                'media_url' => 'https://example.com/promo.jpg',
            ]);
        $boostRes->assertStatus(201);
        $boostId = $boostRes->json('data.id');

        // Pending boost ad must NOT show in public /ads yet
        $this->getJson('/api/v1/ads?placement=home_feed')
            ->assertStatus(200)
            ->assertJsonCount(0, 'data');

        // Admin approves
        $this->app['auth']->forgetGuards();
        $this->actingAs($admin)->post('/admin/ads/' . $boostId . '/approve')->assertRedirect();

        $this->getJson('/api/v1/ads?placement=home_feed')
            ->assertStatus(200)
            ->assertJsonPath('data.0.id', $boostId);

        // 9. Nearby GPS Discovery
        $this->getJson('/api/v1/stores/discover?lat=-6.2010&lng=106.8170&store_type=coffeeshop&only_open=1')
            ->assertStatus(200)
            ->assertJsonPath('data.0.slug', 'kopi-nusantara');

        // 10. Sync POS products only & toggle show_on_home = false
        $this->app['auth']->forgetGuards();
        $this->withHeader('Authorization', 'Bearer ' . $token)
            ->postJson('/api/v1/store/products/sync', [
                'products' => [
                    [
                        'client_uid' => 'p-2',
                        'name' => 'Matcha Latte',
                        'category' => 'Non-Kopi',
                        'price' => 25000,
                        'stock' => 30,
                        'unit' => 'cup',
                        'is_active' => true,
                    ],
                ],
            ])
            ->assertStatus(200)
            ->assertJsonPath('count', 1);

        $this->withHeader('Authorization', 'Bearer ' . $token)
            ->putJson('/api/v1/store/me', [
                'name' => 'Kopi Nusantara',
                'slug' => 'kopi-nusantara',
                'store_type' => 'coffeeshop',
                'show_on_home' => false,
            ])
            ->assertStatus(200)
            ->assertJsonPath('data.show_on_home', false);

        // Hidden from Home discovery when show_on_home = false, but storefront still accessible
        $this->getJson('/api/v1/stores/discover')
            ->assertStatus(200)
            ->assertJsonCount(0, 'data');
        $this->get('/kopi-nusantara')->assertStatus(200)->assertSee('Matcha Latte');
    }
}
