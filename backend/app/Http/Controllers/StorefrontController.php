<?php

namespace App\Http\Controllers;

use App\Models\Store;
use App\Models\StoreCustomer;
use App\Models\StoreOrder;
use App\Models\StoreProduct;
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
            ->with(['products' => fn ($q) => $q->where('is_active', true)->orderBy('category')->orderBy('name')])
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
        $totalAmount = 0.0;
        foreach ($requested as $productId => $qty) {
            $product = $products->get((int) $productId);
            if (!$product) {
                continue;
            }
            $q = (int) $qty;
            $subtotal = round((float) $product->price * $q, 2);
            $totalAmount += $subtotal;
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

        $order = DB::transaction(function () use ($store, $data, $cleanWa, $orderItems, $totalAmount) {
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
                'total_amount' => $totalAmount,
                'status' => 'queued',
            ]);
        });

        return back()->with('order_success', "Pesanan #{$order->order_code} berhasil masuk antrean kasir (POS)!");
    }
}
