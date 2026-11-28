<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class SyncSettingResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'theme_mode' => $this->theme_mode,
            'shuffle_enabled' => $this->shuffle_enabled,
            'repeat_mode' => $this->repeat_mode,
            'eq_preset' => $this->eq_preset,
            'playback_speed' => $this->playback_speed,
            'extra_json' => $this->extra_json ?? [],
            'revision' => $this->revision,
            'client_updated_at' => $this->client_updated_at?->toIso8601String(),
            'updated_at' => $this->updated_at?->toIso8601String(),
        ];
    }
}
