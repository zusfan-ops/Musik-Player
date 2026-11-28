<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\AdCampaign;
use App\Models\AdEvent;
use App\Models\Store;
use App\Models\StoreBooking;
use App\Models\StoreFinanceEntry;
use App\Models\StoreJukeboxRequest;
use App\Models\StoreOrder;
use App\Models\StoreProduct;
use App\Models\StoreVoucher;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

class StoreApiController extends Controller
{
    public function discover(Request $request): JsonResponse
    {
        $query = Store::publiclyVisible()
            ->with(['products' => fn ($q) => $q->where('is_active', true)->limit(4)]);

        $storeType = trim((string) $request->query('store_type', ''));
        if ($storeType !== '' && in_array($storeType, Store::TYPES, true)) {
            $query->where('store_type', $storeType);
        }

        if ($request->boolean('only_open')) {
            $query->where('is_open', true);
        }

        $lat = $request->query('lat');
        $lng = $request->query('lng');
        $hasCoords = is_numeric($lat) && is_numeric($lng);

        if ($hasCoords) {
            $userLat = (float) $lat;
            $userLng = (float) $lng;
            $stores = $query->whereNotNull('latitude')->whereNotNull('longitude')->get()
                ->map(function (Store $s) use ($userLat, $userLng) {
                    $dist = $this->haversineKm($userLat, $userLng, (float) $s->latitude, (float) $s->longitude);
                    $formatted = $this->formatStore($s, includeProducts: true);
                    $formatted['distance_km'] = round($dist, 2);
                    return $formatted;
                })
                ->sortBy('distance_km')
                ->take(10)
                ->values();
        } else {
            $stores = $query->inRandomOrder()
                ->limit(10)
                ->get()
                ->map(fn (Store $s) => $this->formatStore($s, includeProducts: true));
        }

        return response()->json(['data' => $stores]);
    }

    public function show(string $slug): JsonResponse
    {
        $store = Store::publiclyVisible()
            ->where('slug', strtolower(trim($slug)))
            ->with(['products' => fn ($q) => $q->where('is_active', true)->orderBy('category')->orderBy('name')])
            ->first();

        if (!$store) {
            return response()->json(['message' => 'Toko tidak ditemukan.'], 404);
        }

        $store->increment('views_count');

        return response()->json([
            'data' => $this->formatStore($store, includeProducts: true),
        ]);
    }

    public function trackView(Request $request, string $slug): JsonResponse
    {
        $store = Store::publiclyVisible()->where('slug', strtolower(trim($slug)))->first();
        if (!$store) {
            return response()->json(['message' => 'Toko tidak ditemukan.'], 404);
        }

        $data = $request->validate([
            'product_id' => ['nullable', 'integer'],
        ]);

        $store->increment('views_count');
        if (!empty($data['product_id'])) {
            StoreProduct::where('store_id', $store->id)
                ->where('id', (int) $data['product_id'])
                ->increment('views_count');
        }

        return response()->json(['ok' => true]);
    }

    public function ads(Request $request): JsonResponse
    {
        $placement = $request->query('placement', 'home_feed');
        if (!in_array($placement, ['home_feed', 'store_feed'], true)) {
            $placement = 'home_feed';
        }

        $platform = strtolower((string) $request->query('platform', 'unknown'));
        if (!in_array($platform, ['android', 'android_tv', 'windows', 'linux', 'macos', 'ios', 'web', 'unknown'], true)) {
            $platform = 'unknown';
        }
        $installId = $request->query('installation_id');
        $installId = is_string($installId) && preg_match('/^[a-zA-Z0-9\-_]{1,64}$/', $installId) ? $installId : null;
        $userId = $request->user('sanctum')?->id;

        $ads = AdCampaign::where('is_active', true)
            ->where('approval_status', 'approved')
            ->where('placement', $placement)
            ->inRandomOrder()
            ->limit(5)
            ->get();

        if ($ads->isNotEmpty()) {
            AdCampaign::whereIn('id', $ads->pluck('id'))->increment('impressions_count');
            $now = now();
            $rows = $ads->map(fn (AdCampaign $ad) => [
                'ad_campaign_id' => $ad->id,
                'event_type' => 'impression',
                'placement' => $ad->placement,
                'platform' => $platform,
                'installation_id' => $installId,
                'user_id' => $userId,
                'occurred_at' => $now,
            ])->all();
            AdEvent::insert($rows);
        }

        return response()->json([
            'data' => $ads->map(fn (AdCampaign $ad) => [
                'id' => $ad->id,
                'title' => $ad->title,
                'description' => $ad->description,
                'media_type' => $ad->media_type,
                'media_url' => $ad->media_url,
                'target_url' => $ad->target_url,
                'placement' => $ad->placement,
            ]),
        ]);
    }

    public function trackAdClick(Request $request, AdCampaign $ad): JsonResponse
    {
        if ($ad->is_active) {
            $ad->increment('clicks_count');
            $platform = strtolower((string) $request->input('platform', 'unknown'));
            if (!in_array($platform, ['android', 'android_tv', 'windows', 'linux', 'macos', 'ios', 'web', 'unknown'], true)) {
                $platform = 'unknown';
            }
            $installId = $request->input('installation_id');
            $installId = is_string($installId) && preg_match('/^[a-zA-Z0-9\-_]{1,64}$/', $installId) ? $installId : null;

            AdEvent::create([
                'ad_campaign_id' => $ad->id,
                'event_type' => 'click',
                'placement' => $ad->placement,
                'platform' => $platform,
                'installation_id' => $installId,
                'user_id' => $request->user('sanctum')?->id,
                'occurred_at' => now(),
            ]);
        }

        return response()->json(['ok' => true]);
    }

    public function myStore(Request $request): JsonResponse
    {
        $user = $request->user();
        $store = $user->store()->with('products')->first();
        if (!$store) {
            return response()->json(['data' => null]);
        }

        $topProducts = $store->products()
            ->orderByDesc('views_count')
            ->limit(10)
            ->get(['id', 'name', 'price', 'views_count']);

        return response()->json([
            'data' => [
                'store' => $this->formatStore($store, includeProducts: true),
                'has_staff_pin' => !empty($store->staff_pin_hash),
                'analytics' => [
                    'views_count' => $store->views_count,
                    'customers_count' => $store->customers()->count(),
                    'orders_count' => $store->orders()->count(),
                    'queued_orders_count' => $store->orders()->where('status', 'queued')->count(),
                    'bookings_count' => $store->bookings()->count(),
                    'rating_avg' => $store->rating_avg,
                    'rating_count' => $store->rating_count,
                    'top_products' => $topProducts,
                ],
                'orders' => $store->orders()->limit(30)->get(),
                'bookings' => $store->bookings()->limit(30)->get(),
                'customers' => $store->customers()->orderByDesc('last_order_at')->limit(50)->get(),
                'vouchers' => $store->vouchers()->limit(30)->get(),
                'jukebox_requests' => $store->jukeboxRequests()->limit(30)->get(),
                'reviews' => $store->reviews()->limit(20)->get(),
                'boost_ads' => $store->adCampaigns()->limit(20)->get(),
                'finance_entries' => $store->financeEntries()->limit(100)->get(),
            ],
        ]);
    }

    public function upsertMyStore(Request $request): JsonResponse
    {
        $user = $request->user();
        $existing = $user->store;

        $data = $request->validate([
            'name' => ['required', 'string', 'min:2', 'max:120'],
            'slug' => [
                'required',
                'string',
                'min:3',
                'max:64',
                'regex:/^[a-z0-9\-]+$/',
                Rule::notIn(Store::RESERVED_SLUGS),
                Rule::unique('stores', 'slug')->ignore($existing?->id),
            ],
            'store_type' => ['required', Rule::in(Store::TYPES)],
            'description' => ['nullable', 'string', 'max:500'],
            'address' => ['nullable', 'string', 'max:300'],
            'latitude' => ['nullable', 'numeric', 'between:-90,90'],
            'longitude' => ['nullable', 'numeric', 'between:-180,180'],
            'whatsapp_number' => ['nullable', 'string', 'max:30'],
            'tables_count' => ['nullable', 'integer', 'min:0', 'max:200'],
            'google_maps_review_url' => ['nullable', 'url:http,https', 'max:1024'],
            'opening_hours' => ['nullable', 'string', 'max:120'],
            'is_open' => ['sometimes', 'boolean'],
            'staff_pin' => ['nullable', 'digits_between:4,8'],
            'clear_staff_pin' => ['sometimes', 'boolean'],
            'now_playing_title' => ['nullable', 'string', 'max:200'],
            'now_playing_artist' => ['nullable', 'string', 'max:160'],
            'is_active' => ['sometimes', 'boolean'],
            'products' => ['sometimes', 'array', 'max:200'],
            'products.*.client_uid' => ['required', 'string', 'max:80'],
            'products.*.name' => ['required', 'string', 'max:140'],
            'products.*.category' => ['nullable', 'string', 'max:60'],
            'products.*.price' => ['required', 'numeric', 'min:0'],
            'products.*.stock' => ['nullable', 'integer', 'min:0'],
            'products.*.unit' => ['nullable', 'string', 'max:20'],
            'products.*.is_active' => ['sometimes', 'boolean'],
        ]);

        $store = DB::transaction(function () use ($user, $existing, $data) {
            $attrs = [
                'name' => trim($data['name']),
                'slug' => strtolower(trim($data['slug'])),
                'store_type' => $data['store_type'],
                'description' => $data['description'] ?? null,
                'address' => $data['address'] ?? null,
                'latitude' => $data['latitude'] ?? null,
                'longitude' => $data['longitude'] ?? null,
                'whatsapp_number' => $data['whatsapp_number'] ?? $user->phone,
                'tables_count' => $data['tables_count'] ?? ($data['store_type'] === 'coffeeshop' ? 10 : 0),
                'google_maps_review_url' => $data['google_maps_review_url'] ?? $existing?->google_maps_review_url,
                'opening_hours' => $data['opening_hours'] ?? $existing?->opening_hours,
                'is_open' => $data['is_open'] ?? ($existing?->is_open ?? true),
                'is_active' => $data['is_active'] ?? true,
            ];
            if (!empty($data['clear_staff_pin'])) {
                $attrs['staff_pin_hash'] = null;
            } elseif (!empty($data['staff_pin'])) {
                $attrs['staff_pin_hash'] = Hash::make($data['staff_pin']);
            }
            if (array_key_exists('now_playing_title', $data)) {
                $attrs['now_playing_title'] = $data['now_playing_title'];
                $attrs['now_playing_artist'] = $data['now_playing_artist'] ?? null;
            }

            $store = $existing
                ? tap($existing)->update($attrs)
                : Store::create(['user_id' => $user->id, ...$attrs]);

            if (isset($data['products'])) {
                $keptUids = [];
                foreach ($data['products'] as $p) {
                    $keptUids[] = $p['client_uid'];
                    StoreProduct::updateOrCreate(
                        [
                            'store_id' => $store->id,
                            'client_uid' => $p['client_uid'],
                        ],
                        [
                            'name' => trim($p['name']),
                            'category' => trim((string) ($p['category'] ?? 'Umum')) ?: 'Umum',
                            'price' => (float) $p['price'],
                            'stock' => (int) ($p['stock'] ?? 0),
                            'unit' => trim((string) ($p['unit'] ?? 'pcs')) ?: 'pcs',
                            'is_active' => $p['is_active'] ?? true,
                        ]
                    );
                }
                StoreProduct::where('store_id', $store->id)
                    ->whereNotIn('client_uid', $keptUids)
                    ->delete();
            }

            return $store->load('products');
        });

        return response()->json([
            'data' => $this->formatStore($store, includeProducts: true),
        ]);
    }

    public function ordersIndex(Request $request): JsonResponse
    {
        $store = $request->user()->store;
        if (!$store) {
            return response()->json(['data' => []]);
        }

        return response()->json([
            'data' => $store->orders()->limit(50)->get(),
        ]);
    }

    public function updateOrderStatus(Request $request, StoreOrder $order): JsonResponse
    {
        $store = $request->user()->store;
        if (!$store || $order->store_id !== $store->id) {
            return response()->json(['message' => 'Akses ditolak.'], 403);
        }

        $data = $request->validate([
            'status' => ['required', 'in:queued,preparing,completed,cancelled'],
        ]);
        $order->update(['status' => $data['status']]);

        return response()->json(['data' => $order]);
    }

    public function bookTable(Request $request, string $slug): JsonResponse
    {
        $store = Store::publiclyVisible()->where('slug', strtolower(trim($slug)))->first();
        if (!$store) {
            return response()->json(['message' => 'Toko tidak ditemukan.'], 404);
        }
        if ($store->store_type !== 'coffeeshop') {
            return response()->json(['message' => 'Booking meja hanya tersedia untuk toko bertipe coffeeshop.'], 422);
        }

        $data = $request->validate([
            'table_number' => ['required', 'string', 'max:20'],
            'guests_count' => ['required', 'integer', 'min:1', 'max:30'],
            'booking_time' => ['required', 'date'],
            'customer_whatsapp' => ['required', 'string', 'regex:/^[0-9+\-\s]{8,20}$/'],
            'notes' => ['nullable', 'string', 'max:300'],
        ]);

        $user = $request->user();
        $booking = StoreBooking::create([
            'store_id' => $store->id,
            'user_id' => $user->id,
            'customer_name' => $user->name,
            'customer_whatsapp' => preg_replace('/[^0-9+]/', '', $data['customer_whatsapp']) ?: $data['customer_whatsapp'],
            'table_number' => trim($data['table_number']),
            'guests_count' => $data['guests_count'],
            'booking_time' => $data['booking_time'],
            'notes' => $data['notes'] ?? null,
            'status' => 'pending',
        ]);

        return response()->json([
            'message' => 'Booking meja berhasil dikirim.',
            'data' => $booking,
        ], 201);
    }

    public function updateBookingStatus(Request $request, StoreBooking $booking): JsonResponse
    {
        $store = $request->user()->store;
        if (!$store || $booking->store_id !== $store->id) {
            return response()->json(['message' => 'Akses ditolak.'], 403);
        }

        $data = $request->validate([
            'status' => ['required', 'in:pending,confirmed,cancelled'],
        ]);
        $booking->update(['status' => $data['status']]);

        return response()->json(['data' => $booking]);
    }

    public function uploadQris(Request $request): JsonResponse
    {
        $store = $request->user()->store;
        if (!$store) {
            return response()->json(['message' => 'Anda belum memiliki toko.'], 404);
        }

        $request->validate([
            'qris_file' => ['required', 'file', 'mimes:jpg,jpeg,png,webp', 'extensions:jpg,jpeg,png,webp', 'max:5120'],
        ]);

        $file = $request->file('qris_file');
        $ext = strtolower((string) $file->guessExtension());
        if ($ext === 'jpeg') {
            $ext = 'jpg';
        }
        if (!in_array($ext, ['jpg', 'png', 'webp'], true)) {
            return response()->json(['message' => 'Format gambar QRIS tidak didukung.'], 422);
        }

        if ($store->qris_image_url) {
            $oldPath = (string) parse_url($store->qris_image_url, PHP_URL_PATH);
            if (str_contains($oldPath, '/uploads/qris/')) {
                $oldLocal = public_path('uploads/qris/' . basename($oldPath));
                if (File::exists($oldLocal)) {
                    File::delete($oldLocal);
                }
            }
        }

        $destDir = public_path('uploads/qris');
        File::ensureDirectoryExists($destDir);
        $filename = Str::random(32) . '.' . $ext;
        $file->move($destDir, $filename);
        $qrisUrl = asset('uploads/qris/' . $filename);

        $store->update(['qris_image_url' => $qrisUrl]);

        return response()->json([
            'message' => 'QRIS toko berhasil diunggah.',
            'data' => ['qris_image_url' => $qrisUrl],
        ]);
    }

    public function verifyStaffPin(Request $request): JsonResponse
    {
        $store = $request->user()->store()->first();
        if (!$store) {
            return response()->json(['valid' => false, 'message' => 'Toko tidak ditemukan.'], 404);
        }
        if (empty($store->staff_pin_hash)) {
            return response()->json(['valid' => true]);
        }

        $data = $request->validate([
            'pin' => ['required', 'string', 'max:16'],
        ]);

        if (!Hash::check($data['pin'], $store->staff_pin_hash)) {
            return response()->json(['valid' => false, 'message' => 'PIN Owner salah.'], 403);
        }

        return response()->json(['valid' => true]);
    }

    public function storeVoucher(Request $request): JsonResponse
    {
        $store = $request->user()->store;
        if (!$store) {
            return response()->json(['message' => 'Toko belum diaktifkan.'], 404);
        }

        $data = $request->validate([
            'code' => ['required', 'string', 'min:3', 'max:40', 'regex:/^[A-Za-z0-9\-_]+$/'],
            'discount_type' => ['required', 'in:percent,fixed'],
            'discount_value' => ['required', 'numeric', 'min:1'],
            'min_order' => ['nullable', 'numeric', 'min:0'],
            'max_uses' => ['nullable', 'integer', 'min:1'],
            'expires_at' => ['nullable', 'date'],
        ]);

        if ($data['discount_type'] === 'percent' && (float) $data['discount_value'] > 100) {
            return response()->json(['message' => 'Diskon persen maksimal 100%.'], 422);
        }

        $voucher = StoreVoucher::updateOrCreate(
            ['store_id' => $store->id, 'code' => strtoupper(trim($data['code']))],
            [
                'discount_type' => $data['discount_type'],
                'discount_value' => (float) $data['discount_value'],
                'min_order' => (float) ($data['min_order'] ?? 0),
                'max_uses' => $data['max_uses'] ?? null,
                'is_active' => true,
                'expires_at' => $data['expires_at'] ?? null,
            ]
        );

        return response()->json(['data' => $voucher], 201);
    }

    public function deleteVoucher(Request $request, StoreVoucher $voucher): JsonResponse
    {
        $store = $request->user()->store;
        if (!$store || $voucher->store_id !== $store->id) {
            return response()->json(['message' => 'Akses ditolak.'], 403);
        }
        $voucher->delete();

        return response()->json(['ok' => true]);
    }

    public function updateNowPlaying(Request $request): JsonResponse
    {
        $store = $request->user()->store;
        if (!$store) {
            return response()->json(['message' => 'Toko belum diaktifkan.'], 404);
        }

        $data = $request->validate([
            'title' => ['nullable', 'string', 'max:200'],
            'artist' => ['nullable', 'string', 'max:160'],
        ]);

        $store->update([
            'now_playing_title' => isset($data['title']) ? trim((string) $data['title']) ?: null : null,
            'now_playing_artist' => isset($data['artist']) ? trim((string) $data['artist']) ?: null : null,
        ]);

        return response()->json(['ok' => true]);
    }

    public function updateJukeboxStatus(Request $request, StoreJukeboxRequest $jukeboxRequest): JsonResponse
    {
        $store = $request->user()->store;
        if (!$store || $jukeboxRequest->store_id !== $store->id) {
            return response()->json(['message' => 'Akses ditolak.'], 403);
        }

        $data = $request->validate([
            'status' => ['required', 'in:pending,approved,played,rejected'],
        ]);

        $jukeboxRequest->update(['status' => $data['status']]);

        return response()->json(['data' => $jukeboxRequest]);
    }

    public function syncFinance(Request $request): JsonResponse
    {
        $store = $request->user()->store;
        if (!$store) {
            return response()->json(['message' => 'Toko belum diaktifkan.'], 404);
        }

        $data = $request->validate([
            'entries' => ['required', 'array', 'max:300'],
            'entries.*.client_uid' => ['required', 'string', 'max:80'],
            'entries.*.entry_type' => ['required', 'in:income,expense'],
            'entries.*.category' => ['required', 'string', 'max:80'],
            'entries.*.amount' => ['required', 'numeric', 'min:0'],
            'entries.*.payment_account' => ['nullable', 'string', 'max:60'],
            'entries.*.description' => ['nullable', 'string', 'max:300'],
            'entries.*.occurred_at' => ['nullable', 'date'],
        ]);

        DB::transaction(function () use ($store, $data) {
            foreach ($data['entries'] as $item) {
                StoreFinanceEntry::updateOrCreate(
                    [
                        'store_id' => $store->id,
                        'client_uid' => $item['client_uid'],
                    ],
                    [
                        'entry_type' => $item['entry_type'],
                        'category' => trim($item['category']),
                        'amount' => (float) $item['amount'],
                        'payment_account' => $item['payment_account'] ?? null,
                        'description' => $item['description'] ?? null,
                        'occurred_at' => $item['occurred_at'] ?? now(),
                    ]
                );
            }
        });

        return response()->json([
            'data' => $store->financeEntries()->limit(100)->get(),
        ]);
    }

    public function submitBoostAd(Request $request): JsonResponse
    {
        $store = $request->user()->store;
        if (!$store) {
            return response()->json(['message' => 'Toko belum diaktifkan.'], 404);
        }

        $data = $request->validate([
            'title' => ['required', 'string', 'max:140'],
            'description' => ['nullable', 'string', 'max:300'],
            'media_type' => ['required', 'in:image,video'],
            'media_file' => ['nullable', 'file', 'mimes:jpg,jpeg,png,webp,gif,mp4,webm,mov', 'extensions:jpg,jpeg,png,webp,gif,mp4,webm,mov', 'max:25600'],
            'media_url' => ['nullable', 'required_without:media_file', 'url:http,https', 'max:1024'],
            'placement' => ['sometimes', 'in:home_feed,store_feed'],
        ]);

        $mediaUrl = $data['media_url'] ?? '';
        $mediaType = $data['media_type'];

        if ($request->hasFile('media_file')) {
            $file = $request->file('media_file');
            $ext = strtolower((string) $file->guessExtension());
            if ($ext === 'jpeg') {
                $ext = 'jpg';
            }
            if (!in_array($ext, ['jpg', 'png', 'webp', 'gif', 'mp4', 'webm', 'mov'], true)) {
                return response()->json(['message' => 'Format file iklan tidak didukung.'], 422);
            }
            $mediaType = in_array($ext, ['mp4', 'webm', 'mov'], true) ? 'video' : 'image';
            $destDir = public_path('uploads/ads');
            File::ensureDirectoryExists($destDir);
            $filename = Str::random(32) . '.' . $ext;
            $file->move($destDir, $filename);
            $mediaUrl = asset('uploads/ads/' . $filename);
        }

        $ad = AdCampaign::create([
            'title' => trim($data['title']),
            'description' => $data['description'] ?? null,
            'media_type' => $mediaType,
            'media_url' => $mediaUrl,
            'target_url' => url('/' . $store->slug),
            'placement' => $data['placement'] ?? 'home_feed',
            'is_active' => false,
            'approval_status' => 'pending',
            'created_by' => $request->user()->id,
            'store_id' => $store->id,
        ]);

        return response()->json([
            'message' => 'Pengajuan Boost Toko dikirim dan menunggu persetujuan Admin.',
            'data' => $ad,
        ], 201);
    }

    private function haversineKm(float $lat1, float $lon1, float $lat2, float $lon2): float
    {
        $earthRadius = 6371.0;
        $dLat = deg2rad($lat2 - $lat1);
        $dLon = deg2rad($lon2 - $lon1);
        $a = sin($dLat / 2) * sin($dLat / 2)
            + cos(deg2rad($lat1)) * cos(deg2rad($lat2))
            * sin($dLon / 2) * sin($dLon / 2);
        return $earthRadius * (2 * atan2(sqrt($a), sqrt(1 - $a)));
    }

    private function formatStore(Store $store, bool $includeProducts = false): array
    {
        $payload = [
            'id' => $store->id,
            'name' => $store->name,
            'slug' => $store->slug,
            'public_url' => url('/' . $store->slug),
            'store_type' => $store->store_type,
            'description' => $store->description,
            'address' => $store->address,
            'latitude' => $store->latitude,
            'longitude' => $store->longitude,
            'whatsapp_number' => $store->whatsapp_number,
            'tables_count' => $store->tables_count,
            'qris_image_url' => $store->qris_image_url,
            'google_maps_review_url' => $store->google_maps_review_url,
            'opening_hours' => $store->opening_hours,
            'is_open' => $store->is_open,
            'now_playing_title' => $store->now_playing_title,
            'now_playing_artist' => $store->now_playing_artist,
            'rating_avg' => $store->rating_avg,
            'rating_count' => $store->rating_count,
            'is_active' => $store->is_active,
            'views_count' => $store->views_count,
        ];

        if ($includeProducts) {
            $payload['products'] = $store->products->map(fn (StoreProduct $p) => [
                'id' => $p->id,
                'client_uid' => $p->client_uid,
                'name' => $p->name,
                'category' => $p->category,
                'price' => $p->price,
                'stock' => $p->stock,
                'unit' => $p->unit,
                'is_active' => $p->is_active,
                'views_count' => $p->views_count,
            ])->values();
        }

        return $payload;
    }
}
