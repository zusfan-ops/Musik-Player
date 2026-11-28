<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Store extends Model
{
    public const TYPES = ['coffeeshop', 'resto', 'retail', 'jasa', 'umum'];

    public const RESERVED_SLUGS = [
        'admin',
        'api',
        'up',
        'login',
        'register',
        'logout',
        'storage',
        'sanctum',
        'images',
        'css',
        'js',
        'favicon.ico',
        'robots.txt',
    ];

    protected $fillable = [
        'user_id',
        'name',
        'slug',
        'store_type',
        'description',
        'address',
        'latitude',
        'longitude',
        'whatsapp_number',
        'tables_count',
        'is_active',
        'views_count',
    ];

    protected function casts(): array
    {
        return [
            'latitude' => 'float',
            'longitude' => 'float',
            'tables_count' => 'integer',
            'is_active' => 'boolean',
            'views_count' => 'integer',
        ];
    }

    public function owner(): BelongsTo
    {
        return $this->belongsTo(User::class, 'user_id');
    }

    public function products(): HasMany
    {
        return $this->hasMany(StoreProduct::class);
    }

    public function customers(): HasMany
    {
        return $this->hasMany(StoreCustomer::class);
    }

    public function orders(): HasMany
    {
        return $this->hasMany(StoreOrder::class)->orderByDesc('created_at');
    }

    public function bookings(): HasMany
    {
        return $this->hasMany(StoreBooking::class)->orderByDesc('booking_time');
    }

    public function scopePubliclyVisible(Builder $query): Builder
    {
        return $query->where('is_active', true)
            ->whereHas('owner', function (Builder $uq) {
                $uq->where('is_active', true)
                    ->where(function (Builder $sq) {
                        $sq->whereNull('suspended_until')
                            ->orWhere('suspended_until', '<=', now());
                    });
            });
    }
}
