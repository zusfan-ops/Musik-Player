<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class AdCampaign extends Model
{
    protected $fillable = [
        'title',
        'description',
        'media_type',
        'media_url',
        'target_url',
        'placement',
        'is_active',
        'impressions_count',
        'clicks_count',
        'created_by',
    ];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
            'impressions_count' => 'integer',
            'clicks_count' => 'integer',
        ];
    }

    public function events(): HasMany
    {
        return $this->hasMany(AdEvent::class, 'ad_campaign_id');
    }
}
