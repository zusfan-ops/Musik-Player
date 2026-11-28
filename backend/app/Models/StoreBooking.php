<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class StoreBooking extends Model
{
    protected $fillable = [
        'store_id',
        'user_id',
        'customer_name',
        'customer_whatsapp',
        'table_number',
        'guests_count',
        'booking_time',
        'notes',
        'status',
    ];

    protected function casts(): array
    {
        return [
            'guests_count' => 'integer',
            'booking_time' => 'datetime',
        ];
    }
}
