<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class SyncFavoriteResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'client_uid' => $this->client_uid,
            'title' => $this->title,
            'artist' => $this->artist,
            'album' => $this->album,
            'duration_seconds' => $this->duration_seconds,
            'metadata_hash' => $this->metadata_hash,
            'source_type' => $this->source_type,
            'stream_url' => $this->stream_url,
            'is_video' => $this->is_video,
            'client_updated_at' => $this->client_updated_at?->toIso8601String(),
            'updated_at' => $this->updated_at?->toIso8601String(),
        ];
    }
}
