<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class M3uSource extends Model
{
    protected $fillable = [
        'name',
        'category',
        'source_type',
        'source_url',
        'file_path',
        'content_sha256',
        'is_active',
        'created_by',
    ];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
        ];
    }
}
