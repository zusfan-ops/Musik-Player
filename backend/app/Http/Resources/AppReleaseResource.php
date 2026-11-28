<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class AppReleaseResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'version' => $this->version,
            'build_number' => $this->build_number,
            'platform' => $this->platform,
            'abi' => $this->abi,
            'download_url' => $this->download_url,
            'checksum_sha256' => $this->checksum_sha256,
            'size_bytes' => $this->size_bytes,
            'min_supported_version' => $this->min_supported_version,
            'enforce_min_version' => $this->enforce_min_version,
            'release_notes' => $this->release_notes,
            'published_at' => $this->published_at?->toIso8601String(),
        ];
    }
}
