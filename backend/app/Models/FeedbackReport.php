<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class FeedbackReport extends Model
{
    protected $fillable = [
        'user_id',
        'installation_id',
        'category',
        'message',
        'platform',
        'app_version',
        'diagnostics_consent',
        'diagnostics_json',
        'status',
        'admin_notes',
    ];

    protected function casts(): array
    {
        return [
            'diagnostics_consent' => 'boolean',
            'diagnostics_json' => 'array',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
