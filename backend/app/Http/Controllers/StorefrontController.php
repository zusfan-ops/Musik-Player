<?php

namespace App\Http\Controllers;

use App\Models\Store;
use App\Models\StoreBooking;
use App\Models\StoreCustomer;
use App\Models\StoreJukeboxRequest;
use App\Models\StoreOrder;
use App\Models\StoreProduct;
use App\Models\StoreReview;
use App\Models\StoreVoucher;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\View\View;

class StorefrontController extends Controller
{
    public function show(Request $request, string $storeSlug): View
    {
        $slug = strtolower(trim($storeSlug));
        if (in_array($slug, Store::RESERVED_SLUGS, true)) {
            abort(404);
        }

        $store = Store::publiclyVisible()
            ->where('slug', $slug)
            ->with([
                'products' => fn ($q) => $q->where('is_active', true)->orderBy('category')->orderBy('name'),
                'reviews' => fn ($q) => $q->limit(15),
                'vouchers' => fn ($q) => $q->where('is_active', true)
                    ->where(fn ($vq) => $vq->whereNull('expires_at')->orWhere('expires_at', '>', now())),
            ])
            ->first();

        if (!$store) {
            abort(404);
        }

        $store->increment('views_count');

        $rawTable = trim((string) $request->query('meja', ''));
        $selectedTable = preg_replace('/[^a-zA-Z0-9\-]/', '', $rawTable) ?: '';

        return view('storefront', [
            'store' => $store,
            'selectedTable' => $selectedTable,
        ]);
    }

    public function placeOrder(Request $request, string $storeSlug): RedirectResponse
    {
        $slug = strtolower(trim($storeSlug));
        $store = Store::publiclyVisible()->where('slug', $slug)->firstOrFail();

        $data = $request->validate([
            'customer_name' => ['required', 'string', 'min:2', 'max:120'],
            'customer_whatsapp' => ['required', 'string', 'regex:/^[0-9+\-\s]{8,20}$/'],
            'table_number' => ['nullable', 'string', 'max:20'],
            'voucher_code' => ['nullable', 'string', 'max:40'],
            'notes' => ['nullable', 'string', 'max:300'],
            'quantities' => ['required', 'array'],
            'quantities.*' => ['integer', 'min:0', 'max:100'],
        ]);

        $requested = array_filter($data['quantities'], fn ($qty) => (int) $qty > 0);
        if (empty($requested)) {
            return back()->withErrors(['quantities' => 'Pilih minimal 1 produk untuk dipesan.'])->withInput();
        }

        $products = StoreProduct::where('store_id', $store->id)
            ->where('is_active', true)
            ->whereIn('id', array_keys($requested))
            ->get()
            ->keyBy('id');

        $orderItems = [];
        $subtotalAll = 0.0;
        foreach ($requested as $productId => $qty) {
            $product = $products->get((int) $productId);
            if (!$product) {
                continue;
            }
            $q = (int) $qty;
            $subtotal = round((float) $product->price * $q, 2);
            $subtotalAll += $subtotal;
            $orderItems[] = [
                'product_id' => $product->id,
                'client_uid' => $product->client_uid,
                'name' => $product->name,
                'price' => (float) $product->price,
                'qty' => $q,
                'subtotal' => $subtotal,
            ];
        }

        if (empty($orderItems)) {
            return back()->withErrors(['quantities' => 'Produk yang dipilih tidak tersedia.'])->withInput();
        }

        $cleanWa = preg_replace('/[^0-9+]/', '', $data['customer_whatsapp']) ?: $data['customer_whatsapp'];
        $rawVoucher = strtoupper(trim((string) ($data['voucher_code'] ?? '')));

        try {
            $order = DB::transaction(function () use ($store, $data, $cleanWa, $orderItems, $subtotalAll, $rawVoucher) {
                $discountAmount = 0.0;
                $appliedVoucher = null;

                if ($rawVoucher !== '') {
                    $voucher = StoreVoucher::where('store_id', $store->id)
                        ->where('code', $rawVoucher)
                        ->where('is_active', true)
                        ->lockForUpdate()
                        ->first();

                    if (!$voucher) {
                        throw new \RuntimeException('Kode voucher tidak ditemukan atau tidak aktif.');
                    }
                    if ($voucher->expires_at && $voucher->expires_at->isPast()) {
                        throw new \RuntimeException('Kode voucher sudah kedaluwarsa.');
                    }
                    if ($voucher->max_uses !== null && $voucher->used_count >= $voucher->max_uses) {
                        throw new \RuntimeException('Kuota kode voucher sudah habis.');
                    }
                    if ($subtotalAll < $voucher->min_order) {
                        throw new \RuntimeException('Minimal order untuk voucher ini adalah Rp ' . number_format($voucher->min_order, 0, ',', '.'));
                    }

                    if ($voucher->discount_type === 'percent') {
                        $discountAmount = round($subtotalAll * min(100, $voucher->discount_value) / 100, 2);
                    } else {
                        $discountAmount = min($subtotalAll, $voucher->discount_value);
                    }
                    $voucher->increment('used_count');
                    $appliedVoucher = $voucher->code;
                }

                $finalTotal = max(0.0, round($subtotalAll - $discountAmount, 2));

                $customer = StoreCustomer::where('store_id', $store->id)
                    ->where('whatsapp', $cleanWa)
                    ->first();

                if ($customer) {
                    $customer->update([
                        'name' => trim($data['customer_name']),
                        'orders_count' => $customer->orders_count + 1,
                        'last_order_at' => now(),
                    ]);
                } else {
                    $customer = StoreCustomer::create([
                        'store_id' => $store->id,
                        'name' => trim($data['customer_name']),
                        'whatsapp' => $cleanWa,
                        'orders_count' => 1,
                        'last_order_at' => now(),
                    ]);
                }

                return StoreOrder::create([
                    'store_id' => $store->id,
                    'store_customer_id' => $customer->id,
                    'order_code' => 'ORD-' . strtoupper(Str::random(6)),
                    'customer_name' => trim($data['customer_name']),
                    'customer_whatsapp' => $cleanWa,
                    'table_number' => isset($data['table_number']) && trim((string) $data['table_number']) !== ''
                        ? trim((string) $data['table_number'])
                        : null,
                    'notes' => isset($data['notes']) ? trim((string) $data['notes']) ?: null : null,
                    'items_json' => $orderItems,
                    'total_amount' => $finalTotal,
                    'discount_amount' => $discountAmount,
                    'voucher_code' => $appliedVoucher,
                    'status' => 'queued',
                ]);
            });
        } catch (\RuntimeException $e) {
            return back()->withErrors(['voucher_code' => $e->getMessage()])->withInput();
        }

        $msg = "Pesanan #{$order->order_code} berhasil masuk antrean kasir (POS)!";
        if ($order->discount_amount > 0) {
            $msg .= ' Hemat Rp ' . number_format($order->discount_amount, 0, ',', '.') . " ({$order->voucher_code}).";
        }

        return back()->with('order_success', $msg);
    }

    public function submitReview(Request $request, string $storeSlug): RedirectResponse
    {
        $store = Store::publiclyVisible()->where('slug', strtolower(trim($storeSlug)))->firstOrFail();

        $data = $request->validate([
            'reviewer_name' => ['required', 'string', 'min:2', 'max:120'],
            'reviewer_whatsapp' => ['nullable', 'string', 'regex:/^[0-9+\-\s]{8,20}$/'],
            'rating' => ['required', 'integer', 'min:1', 'max:5'],
            'comment' => ['nullable', 'string', 'max:500'],
        ]);

        $cleanWa = !empty($data['reviewer_whatsapp'])
            ? (preg_replace('/[^0-9+]/', '', $data['reviewer_whatsapp']) ?: $data['reviewer_whatsapp'])
            : null;

        $isVerified = false;
        if ($cleanWa) {
            $isVerified = StoreOrder::where('store_id', $store->id)->where('customer_whatsapp', $cleanWa)->exists()
                || StoreBooking::where('store_id', $store->id)->where('customer_whatsapp', $cleanWa)->exists();
        }

        $userId = $request->user('sanctum')?->id;

        DB::transaction(function () use ($store, $data, $cleanWa, $isVerified, $userId) {
            StoreReview::create([
                'store_id' => $store->id,
                'user_id' => $userId,
                'reviewer_name' => trim($data['reviewer_name']),
                'reviewer_whatsapp' => $cleanWa,
                'rating' => (int) $data['rating'],
                'comment' => isset($data['comment']) ? trim((string) $data['comment']) ?: null : null,
                'is_verified_order' => $isVerified,
            ]);

            $agg = StoreReview::where('store_id', $store->id)
                ->selectRaw('COUNT(*) as cnt, AVG(rating) as avg_rating')
                ->first();

            $store->update([
                'rating_count' => (int) ($agg->cnt ?? 0),
                'rating_avg' => round((float) ($agg->avg_rating ?? 0), 2),
            ]);
        });

        return back()->with('order_success', 'Terima kasih atas ulasan dan rating Anda!');
    }

    public function requestJukebox(Request $request, string $storeSlug): RedirectResponse
    {
        $store = Store::publiclyVisible()->where('slug', strtolower(trim($storeSlug)))->firstOrFail();

        $data = $request->validate([
            'requester_name' => ['required', 'string', 'min:2', 'max:120'],
            'table_number' => ['nullable', 'string', 'max:20'],
            'song_title' => ['required', 'string', 'min:2', 'max:200'],
            'artist_name' => ['nullable', 'string', 'max:160'],
            'notes' => ['nullable', 'string', 'max:250'],
        ]);

        StoreJukeboxRequest::create([
            'store_id' => $store->id,
            'requester_name' => trim($data['requester_name']),
            'table_number' => isset($data['table_number']) ? trim((string) $data['table_number']) ?: null : null,
            'song_title' => trim($data['song_title']),
            'artist_name' => isset($data['artist_name']) ? trim((string) $data['artist_name']) ?: null : null,
            'notes' => isset($data['notes']) ? trim((string) $data['notes']) ?: null : null,
            'status' => 'pending',
        ]);

        return back()->with('order_success', "Request lagu \"{$data['song_title']}\" terkirim ke kasir!");
    }
}
