<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class M3uSource extends Model
{
    protected $fillable = [
        'name',
        'category',
        'region',
        'city',
        'language',
        'source_type',
        'source_url',
        'file_path',
        'content_sha256',
        'is_active',
        'status',
        'stream_status',
        'status_reason',
        'scheduled_at',
        'published_at',
        'created_by',
    ];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
            'scheduled_at' => 'datetime',
            'published_at' => 'datetime',
        ];
    }

    public function versions(): HasMany
    {
        return $this->hasMany(M3uSourceVersion::class)->orderByDesc('version_number');
    }

    public function scopePublished(Builder $query): Builder
    {
        return $query->where('is_active', true)
            ->where(function (Builder $q) {
                $q->where('status', 'published')
                    ->orWhere(function (Builder $sq) {
                        $sq->where('status', 'scheduled')
                            ->whereNotNull('scheduled_at')
                            ->where('scheduled_at', '<=', now());
                    });
            });
    }
}
