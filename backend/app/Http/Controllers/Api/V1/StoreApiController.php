<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\AdCampaign;
use App\Models\AdEvent;
use App\Models\Store;
use App\Models\StoreBooking;
use App\Models\StoreOrder;
use App\Models\StoreProduct;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class StoreApiController extends Controller
{
    public function discover(): JsonResponse
    {
        $stores = Store::publiclyVisible()
            ->with(['products' => fn ($q) => $q->where('is_active', true)->limit(4)])
            ->inRandomOrder()
            ->limit(10)
            ->get()
            ->map(fn (Store $s) => $this->formatStore($s, includeProducts: true));

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
                'analytics' => [
                    'views_count' => $store->views_count,
                    'customers_count' => $store->customers()->count(),
                    'orders_count' => $store->orders()->count(),
                    'queued_orders_count' => $store->orders()->where('status', 'queued')->count(),
                    'bookings_count' => $store->bookings()->count(),
                    'top_products' => $topProducts,
                ],
                'orders' => $store->orders()->limit(30)->get(),
                'bookings' => $store->bookings()->limit(30)->get(),
                'customers' => $store->customers()->orderByDesc('last_order_at')->limit(50)->get(),
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
                'is_active' => $data['is_active'] ?? true,
            ];

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
