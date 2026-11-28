<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class SyncedPlaylist extends Model
{
    use SoftDeletes;

    protected $fillable = [
        'user_id',
        'client_uid',
        'name',
        'source_type',
        'source_url',
        'revision',
        'is_enabled',
        'client_updated_at',
    ];

    protected function casts(): array
    {
        return [
            'revision' => 'integer',
            'is_enabled' => 'boolean',
            'client_updated_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function items(): HasMany
    {
        return $this->hasMany(SyncedPlaylistItem::class)->orderBy('position');
    }
}
