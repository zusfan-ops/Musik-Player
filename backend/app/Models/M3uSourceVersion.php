<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class M3uSourceVersion extends Model
{
    protected $fillable = [
        'm3u_source_id',
        'version_number',
        'name',
        'category',
        'region',
        'city',
        'language',
        'source_type',
        'source_url',
        'file_path',
        'content_sha256',
        'status',
        'created_by',
    ];

    public function source(): BelongsTo
    {
        return $this->belongsTo(M3uSource::class, 'm3u_source_id');
    }
}
