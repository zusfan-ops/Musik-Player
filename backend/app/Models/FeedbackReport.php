<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

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

    public function messages(): HasMany
    {
        return $this->hasMany(FeedbackMessage::class, 'feedback_report_id')->orderBy('created_at');
    }
}
