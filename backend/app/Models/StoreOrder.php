<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class StoreOrder extends Model
{
    protected $fillable = [
        'store_id',
        'store_customer_id',
        'order_code',
        'customer_name',
        'customer_whatsapp',
        'table_number',
        'notes',
        'items_json',
        'total_amount',
        'status',
    ];

    protected function casts(): array
    {
        return [
            'items_json' => 'array',
            'total_amount' => 'float',
        ];
    }
}
