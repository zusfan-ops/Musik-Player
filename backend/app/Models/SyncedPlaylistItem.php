<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SyncedPlaylistItem extends Model
{
    protected $fillable = [
        'synced_playlist_id',
        'client_uid',
        'position',
        'title',
        'artist',
        'album',
        'group_title',
        'duration_seconds',
        'metadata_hash',
        'stream_url',
        'is_video',
        'last_position_seconds',
    ];

    protected function casts(): array
    {
        return [
            'position' => 'integer',
            'duration_seconds' => 'integer',
            'is_video' => 'boolean',
            'last_position_seconds' => 'integer',
        ];
    }

    public function playlist(): BelongsTo
    {
        return $this->belongsTo(SyncedPlaylist::class, 'synced_playlist_id');
    }
}
