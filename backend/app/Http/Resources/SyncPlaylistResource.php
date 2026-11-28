<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class SyncPlaylistResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'client_uid' => $this->client_uid,
            'name' => $this->name,
            'source_type' => $this->source_type,
            'source_url' => $this->source_url,
            'revision' => $this->revision,
            'is_enabled' => $this->is_enabled,
            'client_updated_at' => $this->client_updated_at?->toIso8601String(),
            'updated_at' => $this->updated_at?->toIso8601String(),
            'items' => $this->whenLoaded('items', fn () => $this->items->map(fn ($i) => [
                'client_uid' => $i->client_uid,
                'position' => $i->position,
                'title' => $i->title,
                'artist' => $i->artist,
                'album' => $i->album,
                'group_title' => $i->group_title,
                'duration_seconds' => $i->duration_seconds,
                'metadata_hash' => $i->metadata_hash,
                'stream_url' => $i->stream_url,
                'is_video' => $i->is_video,
                'last_position_seconds' => $i->last_position_seconds,
            ])->values()),
        ];
    }
}
