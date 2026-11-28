<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class StoreJukeboxRequest extends Model
{
    protected $fillable = [
        'store_id',
        'requester_name',
        'table_number',
        'song_title',
        'artist_name',
        'notes',
        'status',
    ];

    public function store(): BelongsTo
    {
        return $this->belongsTo(Store::class);
    }
}
