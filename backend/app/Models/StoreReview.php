<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class StoreReview extends Model
{
    protected $fillable = [
        'store_id',
        'user_id',
        'reviewer_name',
        'reviewer_whatsapp',
        'rating',
        'comment',
        'is_verified_order',
    ];

    protected function casts(): array
    {
        return [
            'rating' => 'integer',
            'is_verified_order' => 'boolean',
        ];
    }

    public function store(): BelongsTo
    {
        return $this->belongsTo(Store::class);
    }
}
