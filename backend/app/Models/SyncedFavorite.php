<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SyncedFavorite extends Model
{
    protected $fillable = [
        'user_id',
        'client_uid',
        'title',
        'artist',
        'album',
        'duration_seconds',
        'metadata_hash',
        'source_type',
        'stream_url',
        'is_video',
        'client_updated_at',
    ];

    protected function casts(): array
    {
        return [
            'duration_seconds' => 'integer',
            'is_video' => 'boolean',
            'client_updated_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
