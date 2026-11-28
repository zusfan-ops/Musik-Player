<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class WatchProgress extends Model
{
    protected $table = 'watch_progress';

    protected $fillable = [
        'user_id',
        'content_key',
        'title',
        'content_type',
        'position_seconds',
        'duration_seconds',
        'stream_url',
    ];

    protected function casts(): array
    {
        return [
            'position_seconds' => 'integer',
            'duration_seconds' => 'integer',
        ];
    }
}
