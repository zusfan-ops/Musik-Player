<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class StoreCustomer extends Model
{
    protected $fillable = [
        'store_id',
        'name',
        'whatsapp',
        'orders_count',
        'last_order_at',
    ];

    protected function casts(): array
    {
        return [
            'orders_count' => 'integer',
            'last_order_at' => 'datetime',
        ];
    }
}
