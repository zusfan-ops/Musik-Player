<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class AppRelease extends Model
{
    protected $fillable = [
        'version',
        'build_number',
        'platform',
        'abi',
        'download_url',
        'checksum_sha256',
        'size_bytes',
        'min_supported_version',
        'enforce_min_version',
        'release_notes',
        'is_active',
        'published_at',
    ];

    protected function casts(): array
    {
        return [
            'build_number' => 'integer',
            'size_bytes' => 'integer',
            'enforce_min_version' => 'boolean',
            'is_active' => 'boolean',
            'published_at' => 'datetime',
        ];
    }
}
