<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SyncedSetting extends Model
{
    protected $fillable = [
        'user_id',
        'theme_mode',
        'shuffle_enabled',
        'repeat_mode',
        'eq_preset',
        'playback_speed',
        'extra_json',
        'revision',
        'client_updated_at',
    ];

    protected function casts(): array
    {
        return [
            'shuffle_enabled' => 'boolean',
            'playback_speed' => 'float',
            'extra_json' => 'array',
            'revision' => 'integer',
            'client_updated_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
